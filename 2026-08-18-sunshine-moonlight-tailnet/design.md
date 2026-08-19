# Sunshine + Moonlight 串流接入自建 Tailnet 设计文档

日期:2026-08-18(2026-08-19 补记并加固) · 状态:已完成,已验证 · 实施记录:[implementation.md](implementation.md) · 后续演进:[../2026-08-18-tailnet-exit-singbox/design.md](../2026-08-18-tailnet-exit-singbox/design.md)(tailnet 升级为双 Exit Node + sing-box 分流网关)

## 背景与目标

在外(4G / 异地 WiFi)用 iPad、Android 手机串流家里笔记本(Kubuntu 26.04)的桌面与游戏。技术选型:Moonlight(客户端)+ Sunshine(主机端,开源 GameStream 服务)。

网络两端的硬约束:

- **家宽**:电信光猫(192.168.1.1,不可管理)→ 小米路由(192.168.31.1),双重 NAT。家宽 IPv4 虽是公网地址(114.92.x,端口映射无关型),但无法在光猫上配置入向端口映射(无管理权,桥接需打 10000 未做)。
- **4G 侧**:运营商对称 CGNAT,IPv4 UDP 打洞必然失败。

目标:**任何网络环境下 iPad/Android 都能连上笔记本的 Sunshine**,延迟可玩、一次配置永久有效,并有独立故障域的备份链路。

## 范围

**In scope:**

- VPS 上自建 headscale 控制平面 + 内嵌 DERP 中继 + STUN
- 笔记本 / iPad / Android 三节点接入 tailnet
- 笔记本 Sunshine 主机端(安装、user 级服务化、端口)
- Moonlight 客户端配对,LAN/tailnet/frp 多来源主机条目合并
- frp 中继备份链路(VPS frps + 笔记本 frpc 出站)
- 串流链路故障排查方法与看门狗(2026-08-19 增补)

**Out of scope:**

- tailnet 的翻墙 / Exit Node 用法 → 独立档案 [2026-08-18-tailnet-exit-singbox](../2026-08-18-tailnet-exit-singbox/design.md)
- 光猫桥接 / 端口映射改造(无光猫管理权)
- 境内 DERP 部署(无国内服务器,DERP 只能走美国 VPS)

## 现状分析(设计时)

- VPS(bandwagon,104.194.83.82,美国西海岸)已有:nginx 443 反代 + Let's Encrypt 证书(`bandwagon.signal-align.com`)、frps、xray 服务端
- 笔记本:Kubuntu 26.04,Wayland(KWin)+ NVIDIA 混合显卡,KMS 抓屏可用,nvenc 编码器可用
- 客户端:iPad(desmond-ipad)、一加 15(oneplus-15),均装 Moonlight 与 Tailscale
- 此前无任何远程串流通道;iPad 翻墙依赖 Shadowrocket(iOS 单 VPN 限制,与 Tailscale 互斥)

## 方案设计

### 总体架构

```
                ┌────────── 主路径:自建 Tailnet(headscale @ VPS)──────────┐
                │                                                          │
 iPad ──────────┤  控制平面: headscale(nginx 443 + LE 证书)           │
 Android ───────┤  P2P 直连: WireGuard over IPv6(240e: ↔ 2409:, ~52ms)│
                │  打洞失败兜底: DERP region 999 "bwg"(VPS 内嵌,独此一家)│
                ▼
          笔记本 100.64.0.1(Sunshine)
                │  TCP 47984(HTTPS API/配对) 47989(HTTP) 47990(Web UI) 48010(RTSP)
                │  UDP 47998/47999/48000(视频/音频/控制) 48002 48010
                │
                ┌────────── 备份路径:frp 中继(同一台 VPS)───────────────┐
                └─ laptop.signal-align.com:47984/47989/48010(tcp)      │
                   + 47998-48002/48010(udp) → frps(VPS) → frpc(笔记本) │
```

设计要点:**两条链路共用同一台 VPS 但故障域独立**(headscale/DERP 挂了 frp 照通,反之亦然);Moonlight 侧因 Sunshine uniqueid 相同,LAN / tailnet / frp 三个来源自动合并为**一个主机条目、一份配对**。

### 组件明细

**1. headscale 0.29.3 @ VPS**

- 部署:nginx 443 反代 → headscale 监听 `127.0.0.1:8080`;配置 `/etc/headscale/config.yaml`;systemd `headscale.service`
- `server_url: https://bandwagon.signal-align.com`
- 内嵌 DERP region 999 "bwg" + STUN(UDP 3478)
- 节点:笔记本 `100.64.0.1`、iPad `100.64.0.2`、手机 `100.64.0.3`;用户 id 1 "desmond"(0.29 CLI 用数字 ID)

**2. Sunshine @ 笔记本**(deb 包)

- user 级 systemd 服务 `app-dev.lizardbyte.app.Sunshine.service`(`Alias=sunshine.service`,`WantedBy=graphical-session.target`,`ExecStartPre=/bin/sleep 5` 等网络就绪,`Restart=on-failure`)
- Web UI `https://localhost:47990`(自签证书,浏览器告警属正常;不对外暴露,配对 PIN 在此录入)
- 配置 `~/.config/sunshine/sunshine.conf` 基本全默认(端口、编码器均未改)

**3. frp 备份链路**

- 笔记本 `/etc/frp/frpc.toml` → VPS frps:ssh tcp 6000 + Sunshine 端口 tcp 47984/47989/48010、udp 47998-48002/48010(本地/远程同端口号,Moonlight 要求标准端口)
- VPS ufw 放行;frps.toml `allowPorts` 含 6000-6010 + Sunshine 端口段
- Moonlight 主机名 `laptop.signal-align.com`

### 关键设计决策

| # | 决策 | 理由 |
|---|------|------|
| 1 | 自建 headscale 而非官方 Tailscale 协调服务器 | 免设备数限制;控制数据不出自己的 VPS;DERP、策略全可控 |
| 2 | `derp.urls: []` 清空公共 DERP 列表,只留 VPS 内嵌 region 999 | 自建控制面与 Tailscale 官方 DERP 舰队不 mesh;iPad 曾漫游到国内不可达的 "tok" region 直接断流;只留 bwg 行为可控 |
| 3 | P2P 押注 IPv6(小米路由开 Native IPv6) | 双重 NAT + 对称 CGNAT 下 v4 打洞必败;家宽获得 240e: 公网 v6 后,v6 打洞一次成功,iPad 4G 直连 ~52ms |
| 4 | 保留 frp 作备份链路而非只靠 DERP | 延迟同级(都过美国),但 frp 端口标准明确、独立于 headscale 控制面;headscale 挂掉 / iOS 客户端升级出 bug 时仍有通道 |
| 5 | Sunshine 用 user 级服务而非 root system 服务 | Wayland 会话抓屏(wlgrab/KMS)需要用户会话环境;deb 包自带 user unit,开机随 graphical-session 自启 |
| 6 | 看门狗 timer(2026-08-19 增补) | Sunshine 存在"进程活着、systemd 显示 active,但端口全无监听"的僵尸态,`Restart=on-failure` 检测不到;用 1 分钟级端口探测兜底,触发时先留证再重启 |

### 风险与缓解

| 风险 | 缓解 |
|---|---|
| iPad 上 Shadowrocket 与 Tailscale 互斥且劫持 RTSP 等非标端口,断掉两条链路 | 串流前必须关 Shadowrocket(iOS 单 VPN 限制,二者只能活一个) |
| Moonlight 不退出会话直接断开 → Sunshine 卡 SUNSHINE_SERVER_BUSY,阻塞后续连接 | Moonlight 端正常 Quit Session(长按应用图标);或 `systemctl --user restart sunshine` |
| 开机瞬时端口冲突 → Sunshine 僵尸态(2026-08-19 实发,当时占用者未查明) | 看门狗 60 秒内自动恢复,并在 journal 留下触发时刻端口占用快照 |
| 两条链路共用一台 VPS(单点) | headscale/DERP 与 frp 故障域独立互为备份;VPS 失联可走 tailnet SSH(`ssh desmond@100.64.0.4`)救援 |
| 47984 对 curl 等裸测试返回 "certificate required" | 正常现象:Sunshine API 强制 TLS 客户端证书,勿据此误判服务故障 |

### 验收标准(已全部达成)

- [x] iPad 4G 下经 tailnet 直连笔记本串流可玩(P2P v6,~52ms)
- [x] iPad 添加 `laptop.signal-align.com`(frp 链路)同样可连
- [x] LAN / tailnet / frp 三来源在 Moonlight 中合并为一个主机条目、一份配对
- [x] SSH 备份通道(frp tcp 6000)可用
- [x] 2026-08-19:僵尸态故障 60 秒内自动恢复;看门狗健康路径零动作、手动停止不拉起(反向验证通过)

## 参考链接

- LizardByte Sunshine 文档:https://docs.lizardbyte.dev/projects/sunshine/en/latest/
- Moonlight 客户端(iPad/Android 应用商店)
- headscale:https://github.com/juanfont/headscale
- 日常运维速查见 [implementation.md](implementation.md) 末节

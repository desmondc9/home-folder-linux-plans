# Tailnet 双 Exit Node + sing-box 分流网关 设计文档

日期:2026-08-18 · 状态:已批准,实施中 · 实施计划:[implementation.md](implementation.md)

## 背景与目标

家庭网络中的移动设备(iPad、Android 手机)在 4G/外出场景下需要两类能力:
1. 安全访问家庭设备(Moonlight 串流笔记本、SSH 等)——已通过自建 headscale tailnet 解决(见 [memory: moonlight-sunshine-tailscale-setup])。
2. 科学上网(翻墙)——此前依赖 iPad Shadowrocket,但 iOS 单 VPN 限制使 Shadowrocket 与 Tailscale 互斥。

目标:**任何设备加入 tailnet 后,选择出口节点即可获得翻墙能力**,且具备 Shadowrocket 式的分流体验——国内网站直连、国外/被墙网站走代理、用户可自定义规则。

## 范围

**In scope:**
- 笔记本(Kubuntu 26.04)配置为 tailnet Exit Node,本机 sing-box 对出口流量按 rule-set 分流
- VPS(bandwagon,美国西海岸)配置为第二个 Exit Node(无分流,全局美国 IP,作为笔记本不在线时的兜底)
- 笔记本自身流量统一走 sing-box 分流,V2rayN 退役(验证通过后)
- DNS 防污染:国内域名 AliDNS 直连解析,国外域名经代理解析
- 用户自定义规则通道(强制直连/强制代理)

**Out of scope:**
- 其他平台客户端的翻墙配置(Windows/Mac 等入网后自动获得能力,无需单独工作)
- 国内 VPS / 境内 DERP 部署(暂无国内服务器)
- 光猫桥接改造(用户无控制权)

## 现状分析

- tailnet(headscale 0.29.3 @ VPS, nginx 反代 443, LE 证书)已有 3 节点:笔记本 100.64.0.1、iPad 100.64.0.2、手机 100.64.0.3;P2P 依赖 IPv6(家宽 240e: + 4G 2409:),iPad 直连 ~52ms
- 翻墙链路:V2rayN(Xray 内核)@ 笔记本 → VLESS+Reality+xtls-rprx-vision → VPS:45575(233boy 自建),节点参数已从 `~/.local/share/v2rayN/binConfigs/config.json` 提取
- 笔记本:ip_forward 已为 1;systemd-resolved(DNS=192.168.31.1);tailscaled netfilter 模式默认
- VPS:ufw 已放行 443/tcp、3478/udp、frp 与 Sunshine 端口;xray 服务端在 45575

## 方案设计

### 总体架构

```
iPad/Android ──WireGuard P2P(IPv6,~52ms)──> 笔记本 tailscaled
     │                                          │
     │ (exit node 流量)                    nftables TPROXY
     │                                          ▼
     │                                     sing-box(:7896 tproxy / :10809 mixed)
     │                                          │ 按 rule-set 判定
     │                          ┌───────────────┴────────────────┐
     │                     国内 DIRECT                    国外 PROXY
     │                          ▼                               ▼
     │                    电信家宽直连               VLESS+Reality → VPS → 目标站
     │
     └──Moonlight/SSH 等 tailnet 内部流量 → 直接到笔记本对应服务,不进 sing-box
```

### 关键设计决策

1. **sing-box(v1.13.19)而非 mihomo/Xray**:协议支持最全(VLESS+Reality+vision 原生)、rule-set(.srs)体系声明式自动更新、性能最好、社区最活跃。Xray 是 VPS 服务端,不兼任分流网关。
2. **TPROXY 而非 TUN**:TUN 会在笔记本上新增虚拟网卡,与 tailscaled 的 netfilter 规则、Sunshine 抓屏网络栈存在交互风险;TPROXY(nftables inet 表)只劫 tailscale0 入向 + 本机 OUTPUT,侵入面小,停用即完全回退。
3. **防回环三道豁免**(顺序敏感):
   - mark 0xff:sing-box 自身出站(`routing_mark: 255`)
   - mark 0x80000:tailscaled 自身 WireGuard 流量
   - 目的地址豁免:VPS IP(frp/headscale/DERP 控制面)、私网、100.64.0.0/10(tailnet)、fd7a::/48
4. **分流规则顺序**:`custom-*` 用户规则 > geosite-cn+geoip-cn → direct > geosite-gfw → proxy > **final=proxy**(未命中默认出国,与 Shadowrocket GEOIP-CN-direct 语义一致)
5. **DNS 独立分流**:systemd-resolved 指向 223.5.5.5 → 被 TPROXY 劫持进 sing-box DNS 模块 → 国内 alidns(UDP 直连,CDN 准确)/ 国外 cfdoh(DoH 经 VPS,防投毒)
6. **VPS 作第二出口**:不装 sing-box,plain tailscaled exit node(全局美国 IP),用于笔记本离线时的兜底;客户端侧下拉选择,无自动选优
7. **V2rayN 平滑退役**:验证期内保持运行(10808 兼作安装下载代理),全部验收后取消自启动

### rule-set 清单(SagerNet 官方,7 天自动更新,download_detour=proxy)

| tag | 内容 | 用途 |
|---|---|---|
| geosite-cn | 国内域名 | → direct + alidns |
| geoip-cn | 国内 IP 段 | → direct |
| geosite-gfw | 已知被墙域名 | → proxy + cfdoh |
| custom-direct / custom-proxy | 用户自定义(local source) | 优先级最高 |

### DNS 方案

| 查询 | 路径 | 理由 |
|---|---|---|
| 国内域名 | AliDNS UDP 直连 | 延迟低、CDN 返回就近节点 |
| 国外/被墙域名 | DoH 1.1.1.1 经 VPS | 绕开 GFW DNS 投毒 |

### 已解决的历史问题(根因档案)

**tailnet 客户端经笔记本出口的 v4-only 国外域名不可达**(2026-08-19 定位并修复)

- 现象:iPad/Android 选笔记本为 Exit Node 时,`ipv4.google.com`、`api.ipify.org` 等 v4-only 国外域名打不开;v6 双栈域名正常
- **真正根因(内核 martian source 检查)**:TPROXY 规则给包打 fwmark 1 后,内核在路由时做源地址校验(fib_validate_source),该查找**同样使用 fwmark 1** → 命中策略路由表 100 的 `local default dev lo` → 内核判定源地址(tailnet 客户端的 100.64.x.x)"属于本机" → 从非 lo 接口(tailscale0)收到本地源地址 = martian → **静默丢弃**(无 RST、无 ICMP、不进 INPUT hook)
- 三大谜团的解释:本机 lo 路径 v4 正常(lo 豁免 martian 检查)、v6 正常(IPv6 无此检查)、tproxy 规则计数器涨但 sing-box 收不到包(包在校验阶段被丢)
- 诊断手段:`sysctl -w net.ipv4.conf.all.log_martians=1` 后 dmesg 出现 `martian source (src=100.64.0.x, dev=tailscale0)`;nft trace 显示包死在 mangle prerouting 之后
- **修复**:`sysctl -w net.ipv4.conf.tailscale0.accept_local=1`(允许非 lo 接口接受"本地源"包;tailscale0 是可信内网入口,安全)。持久化:99-exit-node.conf(all/default)+ sing-box-tproxy.service ExecStart(tailscale0 创建后再设一次)
- 走过的弯路(勿重复):0x80000 mark 豁免(实际 v4 出口流量不带此 mark)、iptables vs nftables(无关)、REDIRECT 替代 TPROXY(无关)、TS_USERSPACE=false(无关)、独立 v4 监听端口(无关)、DNS64/QUIC/MagicDNS(真实存在的独立问题,已各自修复)

## 验收标准

1. iPad(4G,exit=笔记本):myip.ipip.net 显示家宽 IP;google.com 可访问且 api.ipify.org 显示 VPS IP;Moonlight 串流正常
2. iPad(exit=VPS):myip.ipip.net 显示美国 IP
3. Android 同 1
4. 自定义规则演练:custom-proxy.json 加入测试域名后该域名走代理,移除后恢复
5. 本机:不带代理参数的 curl 国内外均符合分流预期;frpc/sunshine/tailscaled/headscale 回归正常
6. DNS:taobao 解析到国内 IP,google 解析到真实 IP(非投毒段)

## 参考

- sing-box 配置:`/etc/sing-box/config.json`(源文件 `~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/`)
- TPROXY 规则:`/etc/sing-box/tproxy.nft` + `sing-box-tproxy.service`
- 节点参数来源:`~/.local/share/v2rayN/binConfigs/config.json`
- 计划与进度:[implementation.md](implementation.md)

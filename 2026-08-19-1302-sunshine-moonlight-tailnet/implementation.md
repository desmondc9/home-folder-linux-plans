# Sunshine + Moonlight + Tailnet 实施记录

> 补记档案:主体搭建完成于 2026-08-18(细节依据当时会话与落盘配置回溯);Task 7(僵尸态排查 + 看门狗)为 2026-08-19 实时记录,含验证证据。无待执行步骤,仅供复现与排障参考。

**Goal:** iPad/Android 在任意网络下串流笔记本桌面/游戏:自建 headscale tailnet 为主链路(IPv6 P2P),frp 中继为备份链路,Sunshine 以 user 服务常驻笔记本。

**Architecture:** 见 [spec.md](spec.md) 总体架构图。两链路共用 VPS 但故障域独立;Moonlight 依 Sunshine uniqueid 合并多来源主机条目。

**Tech Stack:** Sunshine 2026.516(deb)/ Moonlight 1.x(iOS/Android)/ headscale 0.29.3 / tailscale 1.102.2 / frp

---

### Task 1: VPS 部署 headscale + 内嵌 DERP + STUN ✅ 2026-08-18

- [x] 安装 headscale 0.29.3,监听 `127.0.0.1:8080`,nginx 443 反代 + LE 证书(`certbot --nginx`,`server_url: https://bandwagon.signal-align.com`)
- [x] 内嵌 DERP region 999 "bwg";STUN UDP 3478;**`derp.urls: []` 清空公共 DERP**(iPad 曾漫游到不可达的官方 "tok" region 断流,自建 DERP 又不与官方舰队 mesh)
- [x] 创建用户:`headscale users create desmond`(内部 id=1,0.29 CLI 认数字)
- [x] VPS ufw 放行 443/tcp、3478/udp

### Task 2: 三节点接入 tailnet ✅ 2026-08-18

- [x] VPS 签发预授权密钥:`headscale preauthkeys create --user 1`(注意是数字 1,非用户名)
- [x] 笔记本:`tailscale up --login-server https://bandwagon.signal-align.com` → `100.64.0.1`
- [x] iPad(desmond-ipad)→ `100.64.0.2`;一加 15(oneplus-15)→ `100.64.0.3`,均用官方 Tailscale 客户端填自建服务器 + 预授权密钥
- [x] 小米路由开启 IPv6 "Native",笔记本获得 240e: 公网 v6;验证 iPad 4G 下 `tailscale status` 显示 direct ~52ms(P2P 仅 v4 打洞必败——家双重 NAT + 4G 对称 CGNAT)

### Task 3: 笔记本 Sunshine 主机端 ✅ 2026-08-18

- [x] 安装 Sunshine deb(`apt`/官网包);user 级服务 `app-dev.lizardbyte.app.Sunshine.service` 随 graphical-session 自启,`systemctl --user enable --now` 后 `~/.config/systemd/user/sunshine.service` 别名软链即生成
- [x] 首次访问 `https://localhost:47990`(自签证书,浏览器点"高级→继续";401 = 要求登录,属正常)设用户名/密码
- [x] 确认端口全监听:`ss -tln | rg '479|480'` → TCP 47984/47989/47990/48010(UDP 47998-48002/48010 由会话按需建立)
- [x] 确认编码/抓屏:日志出现 nvenc + KMS(Wayland 下 wlr-export-dmabuf 缺失无碍,KMS 抓屏正常)

### Task 4: Moonlight 客户端配对 ✅ 2026-08-18

- [x] iPad/Android Moonlight 添加主机 `100.64.0.1`(tailnet)与 `laptop.signal-align.com`(frp);同一 Sunshine uniqueid → 自动合并为一个主机条目,只需配对一次
- [x] 配对 PIN 录入 Sunshine Web UI(`https://localhost:47990` → PIN 页)
- [x] 验证:4G 下经 tailnet 直连串流 ~52ms 可玩;frp 链路同样出画面
- [x] 使用守则:串流前关 Shadowrocket(iOS 单 VPN 且劫持 RTSP 端口);退流用 Quit Session(长按应用图标),勿直接杀客户端

### Task 5: frp 备份链路 ✅ 2026-08-18

- [x] VPS frps `allowPorts` 含 6000-6010 + Sunshine 端口段;ufw 放行
- [x] 笔记本 `/etc/frp/frpc.toml`(root 权限配置):ssh tcp 6000;Sunshine tcp 47984/47989/48010、udp 47998-48002/48010,**本地/远程同端口号**(Moonlight 要求标准端口)
- [x] 验证:`ssh -p 6000 localhost`(经 VPS 回环)与 Moonlight frp 链路均可通

### Task 6: 已知坑位登记(无需重查) ✅ 2026-08-18

- [x] 47984 对 curl 返回 "certificate required" = 正常(API 强制 TLS 客户端证书)
- [x] SUNSHINE_SERVER_BUSY(断流不退会话)→ Quit Session 或 `systemctl --user restart sunshine`
- [x] VPS AAAA 记录勿写子网前缀裸地址(`::` 结尾)→ 详见 memory 教训

### Task 7: 僵尸态故障排查 + 看门狗 ✅ 2026-08-19

**故障**:iPad Moonlight 连不上 100.64.0.1,且本机 `https://localhost:47990` 无效页面。

- [x] **证据收集**:`tailscale ping desmond-ipad` 6ms 直连(网络无辜)→ `curl -k https://localhost:47990` 连接拒绝 → `ss -tlnp` 发现 Sunshine **零端口监听**但进程活着、systemd 显示 active → 日志定位 `Fatal: Couldn't bind RTSP server to port [48010], Address already in use`(12:57:10 重启机器后 1 分钟内的一次性端口冲突),随后半截关闭流程(`Unmapping UPNP ports...` 为末行)未退出 → 僵尸态
- [x] **排除系统/用户单元冲突假设**:dpkg 仅带 user 单元;系统日志无 root sunshine;flatpak 无;`/etc/xdg/autostart`、`~/.config/autostart` 无条目;`~/.config/systemd/user/sunshine.service` 仅为 enable 别名软链。占用者(幽灵)未查明,出现即消失
- [x] **修复**:`systemctl --user restart app-dev.lizardbyte.app.Sunshine.service` → 四端口恢复监听;`curl https://localhost:47990` 与 `https://100.64.0.1:47990` 均 401(服务正常)
- [x] **看门狗安装**:`~/.local/bin/sunshine-watchdog.sh` + `~/.config/systemd/user/sunshine-watchdog.{service,timer}`(开机 3 分钟后每分钟检查):仅当"服务 active 且 48010 无监听"才先快照端口占用到 journal 再 restart;**手动停止的服务绝不拉起**
- [x] **验证**:健康路径零动作(exit 0);反向测试(stop Sunshine 后跑看门狗)保持 inactive 不拉起;重启后端口恢复

---

## 日常运维速查

```bash
# Sunshine 状态/重启/日志
systemctl --user status  app-dev.lizardbyte.app.Sunshine.service
systemctl --user restart app-dev.lizardbyte.app.Sunshine.service
journalctl --user -u app-dev.lizardbyte.app.Sunshine.service -f

# 端口健康(四行才算活)
ss -tln | rg '479|480'

# 看门狗(触发记录在这里,含重启前端口占用快照)
journalctl --user -u sunshine-watchdog.service --since today

# tailnet 链路
tailscale status && tailscale ping desmond-ipad

# VPS 侧(headscale/DERP/frps,经 tailnet SSH 救援通道)
ssh desmond@100.64.0.4
headscale --config /etc/headscale/config.yaml nodes list

# 串流前检查(iPad):Shadowrocket 必须关闭
```

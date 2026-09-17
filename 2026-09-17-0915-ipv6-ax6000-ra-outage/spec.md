# 小米 AX6000 IPv6 断网排查：odhcpd RA 服务挂死 + 客户端免疫层

- 环境: WSL2 Ubuntu 26.04 @ Win11 耀世15Pro（mirrored networking, 宿主 sing-box TUN 分流）；网络拓扑 = 电信光猫（智能网关，路由模式 192.168.1.1）→ 小米 AX6000（RA72, 固件 1.0.122, WAN DHCP 192.168.1.96, LAN 192.168.31.1）→ 2×红米 AX6S（RB03, 有线回程 mesh, 客厅 .76 / 主卧 .89）
- 日期: 2026-09-16 16:50 故障始发；2026-09-17 09:15–11:14 排查与修复；同日 11:10 冷启后全面恢复
- 关联: [singbox-bilibili-dns-stall](../2026-09-13-2219-singbox-bilibili-dns-stall/)（同机 sing-box DNS 前案）、[tailnet-exit-singbox](../2026-08-18-2224-tailnet-exit-singbox/)（IPv6 对 tailnet P2P 是硬依赖）、`~/docs/network-access-china.md`

## 背景与症状

9/16 16:50 起，浏览器访问国内网站全部失败，而 sing-box 代理的国外网站完全正常——症状反直觉。本机出网路径：宿主 Windows sing-box TUN 分流（国内直连/国外 VLESS→VPS 104.194.83.82）。

**误导性症状的机制**（本次最大学到的点）：Chrome 对国内双栈站优先连 IPv6 → sing-box TUN 在**本地替它完成 TCP 握手**（gvisor/mixed stack）→ 浏览器认为 v6 成功、Happy Eyeballs 不再回退 v4 → sing-box direct outbound 向外拨 IPv6 全部超时/不可达 → 5 秒后 RST。国外站走 VPS（v4 + 远程解析）不受影响。于是"v6 断"表现为"国内全挂、国外全好"。

## 排查时间线（证据链）

1. **分层测试**：宿主 `curl -4` 国内站 200/0.4s；`curl -6` 5s 后 RST；sing-box 日志自 9/16 16:50:14 起刷屏 `dial tcp [240e:…]:443: i/o timeout`——IPv6 出网黑洞，v4 完好
2. **路由器软重启（09:31）后恶化**：客户端全局 v6 地址消失、只剩 ULA `fd7a:6176:ade5:…`（后又过期）；网卡却学到路由器新 RDNSS `240e:388:a44c:6610::1`（前缀 388 ≠ 昨天的 389:a35b ≠ 路由器当前 389:a53e → 该 RA 并非 AX6000 当前配置所发，来自干扰源，见第 6 条）
3. **Windows 侧判据**：`netsh int ipv6 show siteprefixes` 空、Wi-Fi 仅 link-local、无 RA 默认路由——客户端收不到任何前缀通告
4. **路由器 API 自检**（登录算法见 implementation.md）：`ipv6_status` 显示 AX6000 自认为一切正常——WAN `240e:389:a53e:d00:…/128`、PD `240e:389:a53e:d10::`、LAN `…::1/64`；即 DHCPv6-PD 一直在正常工作
5. **mesh 逐段排除**：Windows 关联在主卧 RB03（BSSID a4:39:b3:71:2f:98），但 NDP（ping 路由器 LAN `240e:389:a53e:d10::1` 通 0–1ms）和 DHCPv6（拿到 `…::29b`）都能穿过 RB03 到主路由——卫星的多播转发无辜，**唯独 RA 不来**；手机站主路由旁测 v6 同样不通 → 排除"仅从节点问题"
6. **干扰源**：LAN 内 Apple 设备（192.168.31.59, MAC a8:51:ab:96:be:1d, AirPlay+62078 开放）以隐私 LL 顶着 router 标志通告自己的 ULA `fdfd:a14e:53c0::/64`——异常但非主因
7. **软切换无效、冷启有效**：API `set_wan6` off→on（等价于后台开关 IPv6）救不活 RA；11:10 全机重启后 RA 约 **100 秒**到达，全部恢复

## 根因（两段式故障，同源于 AX6000 固件）

1. **9/16 16:50（黑洞型）**：上游 PD 前缀轮换（240e:389:a35b → …）后 AX6000 未跟随，继续向 LAN 通告已失效的旧前缀——客户端地址"看起来正常"但上游不可达
2. **9/17（无 RA 型）**：AX6000 重启后 v6 用户态服务半死：DHCPv6 server 存活（能发地址）、odhcpd/RA 通告功能未恢复（无 PIO、无默认路由、无 RDNSS）——`set_wan6` 软切换不重启该守护进程，唯冷启可治

**责任判定：小米 AX6000 固件（RA/PD 状态机）。** 电信 ISP 与光猫全程正常：v4 无恙、PD 前缀持续下发（重启后即拿到新 PD `240e:389:a53e:d10::` 即为实证）。RB03 卫星、光猫、ISP 均排除。

## 已实施：客户端免疫层（详情与回滚见 implementation.md）

本机（Win11 耀世15Pro）三处改动，使"路由器 v6 再挂"不再表现为国内站打不开：

1. sing-box DNS 拒答 AAAA（`query_type: AAAA → reject` + `strategy: ipv4_only`）——浏览器永远走 v4，不踩 v6 黑洞；Tailscale peer 走 IP 不受影响
2. Wi-Fi 网卡静态 DNS（223.5.5.5 + fdfe:dcba:9876::2）——堵住"路由器 DNS / RA-RDNSS 返回真 AAAA"的泄漏路径
3. `tailscale set --accept-dns=false`——堵住 MagicDNS 上游返回真 AAAA 的泄漏路径（副作用：`*.tailnet.internal` 名称不再解析）

## 根治路线（未实施，按预算/折腾度排序）

IPv6 对本 tailnet 是硬依赖（P2P 直连 ~52ms vs DERP 美国中继），不能关闭，故根治 = 把 RA/PD 从小米固件挪给成熟实现：

- **A. TP-Link Omada**（ER707-M2 + 3×EAP653/773, ~¥2000, 国行保修）
- **B. Ubiquiti UniFi**（CG Ultra + U6+/U7 Pro, ~¥3000–4000, v6 控制粒度最强）
- **C. GL.iNet Flint 2 当网关 + 三台小米降级 AP**（~¥600, 最便宜）
- **D. RB03 刷 OpenWrt 当主路由**（设备现成, OpenWrt 官方支持）／ AX6000 SSH 解锁刷机（kjfx/AX6000 教程, 有变砖风险）
- 有线回程已就位 → 无需无线 mesh，AC+AP 有线架构即可；光猫保持路由模式不动（PD 正常）

**当前采纳：临时方案 = 每次故障手动重启 AX6000**（RA 约 100s 恢复；复发诱因大概率是电信侧 PD 轮换/光猫重拨）。

## 验收标准（2026-09-17 11:10 全部通过）

- [x] 路由器重启后 Windows `siteprefixes` 出现 `240e:389:a53e:d10::/64`
- [x] Wi-Fi 获得 SLAAC/DHCPv6 全局地址 + RA 默认路由（via fe80::d635:…）
- [x] 宿主 ping `2400:3200::1`（阿里 DNS v6）通，12ms 真实 RTT
- [x] 国内网站 v4 直连正常（curl 200），国外经 VPS 正常
- [ ] 手机 `v6.ipw.cn` 复测（待用户抽查）

## 风险与遗留

- **复发**：固件 bug 未修，PD 轮换或下次重启可能再触发 → 照"手动重启"处置；根治待排期
- **Apple 干扰源**（192.168.31.59 的 ULA RA）未处理：建议找出该设备（iPhone/iPad）关闭个人热点/网络共享
- **Windows 欠一次重启**：当日动过 DNS/TUN/服务多次，建议近期重启清状态
- 路由器管理密码在排查会话中传输过，建议择机修改

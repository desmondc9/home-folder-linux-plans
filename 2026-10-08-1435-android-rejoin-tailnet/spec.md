# 一加 15 重置后重新加入 headscale tailnet

日期: 2026-10-08 · 状态: 已完成(入网+数据面验证通过;手机端后台常驻待设 Always-On VPN)· 实施记录: [implementation.md](implementation.md)
- 环境: 操作机 WSL2 Ubuntu @ Windows 11 笔记本 YAOSHI15PRO(node 10,经 interop 调 tailscale.exe、经 ssh 免密代跑 VPS);headscale v0.29.4 @ Bandwagon VPS brave-goose-1(2026-10 VPS 安全加固中由 0.29.3 升级,见 vps-security-monitoring-hardening 档案);客户端 Android 官方 Tailscale App(一加 15 / ColorOS)

## 背景与目标

一加 15 手机重置,原节点 node 3(`oneplus-15`,100.64.0.3,2026-08-18 入网)的节点私钥随重置销毁,永久失联。目标:新系统重新装入 tailnet,恢复与既有节点(VPS brave-goose-1、yaoshi15pro-win 等)的互通;顺带清理失联副本节点。

## 方案(沿用 [2026-09-22-1956-win11-tailnet-join](../2026-09-22-1956-win11-tailnet-join/spec.md) 的既定流程)

```
[VPS]  删失联 node 3 → 签一次性 preauth key(nodes delete / preauthkeys create --user 1 --expiration 1h)
[手机]  官方 Tailscale App: Accounts → ⋮ → Use an alternate server
        → https://headscale.signal-align.com(弹出的登录页关掉)
        → ⋮ → Use an auth key → 粘贴 key → Connect
[验证]  nodes list 上线 + 本机 tailscale ping 数据面
```

- 控制面入口用规范域名 `headscale.signal-align.com`(2026-09-22 挂载的并行入口,win11 入网已验证可注册;server_url 仍是旧域名,preauth 流程不依赖它)
- Android 客户端无 CLI,auth key 是自建 headscale 下唯一可靠的注册路径(社区共识:纯 alternate-server 登录流程会卡在 auth URL,headscale 不提供该交互页)
- preauth key 红线:值只经聊天通道交用户手机录入,不写入任何 git 跟踪文件(本文以 `__PREAUTH_KEY_REDACTED__` 占位)

## 关键发现

1. **IP 分配回填低位空洞(修正旧结论)**:新节点拿到 **100.64.0.1** 而非顺延的 .11。2026-09-22 档案"headscale 分配计数器不复用"只在**同一进程生命周期内**成立;headscale 跨重启后按低位空洞回填(.1 自 09-22 删 node 1 起空闲)。影响:100.64.0.1 是旧 Kubuntu Sunshine 的历史地址,指向它的旧引用(如 Moonlight 主机条目)如今指向手机——旧引用本已随 Kubuntu 退役失效,无实际影响,但"新节点会拿到陈年旧 IP"这一点以后引用 tailnet IP 时要警惕。
2. **中文设备名**:手机上报 hostname `一加 15`,节点名被压成 `15`(非 ASCII 丢弃)。服务器侧 rename 恢复 `oneplus-15`;0.29 语法是**位置参数** `nodes rename NEW_NAME --identifier N`(无 `--new-name` flag)。JSON 输出里 `name`=客户端上报 hostname、`given_name`=服务器侧命名(rename 改的是后者),`online: null` 即 false。
3. **ColorOS 后台杀 VPN**:注册成功约 2 分钟后节点离线(06:50:11Z 最后心跳,疑锁屏/切后台触发),服务端侧一切正常。需手机端设 Always-On VPN + 电池不优化才能常驻。

## 验收结果

- [x] node 11 注册上线(06:47Z),100.64.0.1 + fd7a:115c:a1e0::1,user desmond,preauth key id 9 已消耗(一次性,07:45Z 自动作废)
- [x] 数据面:本机(node 10)`tailscale ping 100.64.0.1` 通,direct 192.168.31.82:57030(手机与电脑同在小米路由 LAN,直连);注册后 2 分钟内已有 tx 6.6MB / rx 1.1MB 真实流量
- [x] node 11 rename → `oneplus-15`;node 8(`oneplus-15-sfa`,即 [2026-08-22-1404-android-singbox-client](../2026-08-22-1404-android-singbox-client/spec.md) SFA v3 一体化单 VPN 的注册节点)已删(用户确认)
- [x] 手机端短暂离线定性为 ColorOS 杀后台,非服务端问题(重开 App 即回线)

## Follow-up(可选)

- 手机要恢复 SFA v3 一体化单 VPN(sing-box 内嵌 tailscale endpoint,原 node 8 方案):需重新导入 SFA 配置 + 注册新节点(新 preauth key)——重置后旧密钥已失;Android 单 VPN 限制下与本次官方 App 注册(node 11)二选一
- 手机端设置:系统设置 → VPN → Tailscale → 始终开启的 VPN;Tailscale 电池优化设为"不优化"

## 性能与容量

- 纯网络运维操作,无代码/DB/查询变更,Step G 触发项:无。
- 已知容量项复述:yaoshi15pro-win 作为出口的用户态转发 ~8Mbps 天花板(2026-09-12 实测)对手机端仍适用。

## 参考

- 流程母本: [../2026-09-22-1956-win11-tailnet-join/](../2026-09-22-1956-win11-tailnet-join/spec.md)
- 原始入网(2026-08-18 三节点): [../2026-08-19-1302-sunshine-moonlight-tailnet/](../2026-08-19-1302-sunshine-moonlight-tailnet/spec.md)
- SFA v3 与 node 8 由来: [../2026-08-22-1404-android-singbox-client/](../2026-08-22-1404-android-singbox-client/spec.md)

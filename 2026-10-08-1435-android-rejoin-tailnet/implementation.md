# 一加 15 重置后重新入网 实施记录

**Goal:** 重置后的一加 15 重新加入 headscale tailnet,拿到稳定节点身份并恢复与全 tailnet 互通。
**Spec:** [spec.md](spec.md)

> 时间线均为 UTC(本地 +8)。VPS 侧由 AI 在 YAOSHI15PRO 的 WSL2 经 ssh 代跑(`sudo -n` NOPASSWD);手机侧用户手动执行。

### Task 1: VPS 侧准备 ✅ 2026-10-08 06:44Z

- [x] 核实现状:`nodes list` 确认 node 3(`oneplus-15`,100.64.0.3)offline 自 09-22;node 8(`oneplus-15-sfa`)同日失联
- [x] 删 node 3:`nodes delete --identifier 3 --force` → "Node deleted"(释放主机名)
- [x] 签一次性 preauth key:`preauthkeys create --user 1 --expiration 1h` → key id 9,值 `__PREAUTH_KEY_REDACTED__`(经聊天通道交用户手机录入;已消耗,07:45Z 自动作废)

### Task 2: 手机侧入网(用户执行)✅ 06:47Z

- [x] 官方 Tailscale App:Accounts → ⋮ → **Use an alternate server** → `https://headscale.signal-align.com`(弹出的登录页关闭)
- [x] ⋮ → **Use an auth key** → 粘贴 preauth key → 主界面 **Connect**
- [x] 结果:node 11 注册,**100.64.0.1** + fd7a:115c:a1e0::1(非顺延 .11——分配器回填低位空洞,见 spec 关键发现 1)

### Task 3: 验证 ✅ 06:48–06:50Z

- [x] `nodes list`:node 11 online(user desmond)
- [x] 本机 interop `tailscale.exe status`:peer 显示 active;`ping 100.64.0.1` → pong via 192.168.31.82:57030(同 LAN direct)
- [x] 流量:tx 6.6MB / rx 1.1MB(注册后 2 分钟内)

### Task 4: 收尾(用户确认后)✅ 06:50Z

- [x] `nodes rename oneplus-15 --identifier 11` → "Node renamed"(⚠️ NEW_NAME 是**位置参数**,`--new-name` 会报 unknown flag;验证走 `nodes list -o json` 的 `given_name` 字段)
- [x] 删 node 8(`oneplus-15-sfa`,SFA v3 注册节点,失联 15 天;用户确认)
- [x] 遗留观察:06:50:11Z 后手机无心跳(ColorOS 锁屏/切后台杀 VPN),非服务端问题;对策见 spec Follow-up(Always-On VPN + 电池不优化)

### Task 5: 归档 ✅

- [x] spec.md / implementation.md / README 索引补行
- [x] Notebook 同步:本机(WSL)无 `~/Notebook`(Kubuntu 时代产物),跳过
- [x] gitleaks 扫描无 leaks → commit + push main

## 备忘(可迁移经验)

- Android 官方客户端接自建 headscale 的可靠注册路径 = **alternate server + auth key 两步**;纯登录流程会卡在 auth URL(headscale 无该交互页)
- 0.29 `nodes list -o json` 字段语义:`name`=客户端上报 hostname、`given_name`=服务器侧命名(rename 改后者)、`online: null` 即 false
- IP 分配经验:headscale 进程生命周期内单调递增不复用;**跨重启会回填低位空洞**——新节点可能拿到很久以前释放的地址,引用 tailnet IP 的旧配置要警惕
- 手机(OnePlus/ColorOS)Tailscale 常驻三件套:Always-On VPN、电池不优化、最近任务锁定

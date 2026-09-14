# Win11 关机 >30 秒:WSLService(Windows 侧)挂死两个 30s 超时,Ubuntu VM 一秒就关完了

日期:2026-09-14 · 状态:已修复(4 步全部落地并核验),**待下次自然关机回归验证** · 流程:diagnosing-bugs skill(全程自 WSL 经 powershell.exe interop 取证,零猜测)

- 环境:Windows 11 物理机 DESKTOP-J7NBNU4(23H2,build 22631);WSL2 2.7.14.0 / Ubuntu 26.04(systemd=true、mirrored networking、rootless podman 迁移自 09-11);排查与修复执行均自 WSL 侧 interop 完成

## 症状

用户感知关机需 30 秒以上才熄屏;问"是 Windows 11 进程还是 WSL Ubuntu 进程拖慢"。

## 证据链(2026-09-14 00:27 关机周期,System 日志 + WSL journal 双侧对表)

```
00:27:22  [User32/1074]   RuntimeBroker 发起 power off(用户点击关机)
00:27:25  [Winlogon/7002] CEIP logoff 通知(噪音)
00:27:25→26  WSL 内 systemd:收到信号 → 全部 unit 停止 → poweroff.target → Journal stopped
                         ← Ubuntu VM 整个关机过程 ≤1 秒
00:27:55  [SCM/7011]      等 WSLService 事务响应超时 30000ms   ← VM 已死 30 秒,它还在挂
00:28:25  [SCM/7011]      等 WSLService 事务响应超时 30000ms   ← 第二个 30 秒
00:28:25  [SCM/7000/7009] Windows Camera Frame Server Monitor 启动/连接超时 30s(转换期噪音,陪衬)
00:28:29  [Kernel-Power/107] 转换结束
```

**结论:~60s 的等待全部来自 WSLService(WSL 2.7.14 的 Windows 服务)本身,不是 Ubuntu 进程**——VM 关机 1 秒完成,WSLService 在 VM 已死后仍不响应 SCM 的停止请求。该挂死模式上游有同类报告(microsoft/WSL #8529:`wsl --shutdown` 挂 ~30s 等)。

**间歇性佐证**:09-12 23:22、09-13 22:39 两次关机均无 WSLService 超时——仅当关机瞬间 WSL VM 活着且 WSLService 状态不佳时触发。而本机 VM 永不空闲退出(见根因),所以总是站在关机关键路径上。

另:Diagnostics-Performance 日志(关机性能标准证据源)非管理员不可读,本案用 System 日志 7011/7009/7000(消息体直接点名服务)+ WSL journal 时间戳双侧对表替代。

## 次要发现:那次"关机"根本没关成,变成整夜睡眠

Power-Troubleshooter/1:**Sleep 2026-09-13 16:27:25Z(本地 00:27:25)→ Wake 2026-09-14 00:59:06Z(本地 08:59:06)**,Wake Source: Unknown。且该周期无 6005/6006(EventLog 起/止)、无 Kernel-Boot 27(快速启动恢复标记)→ 排除冷启动与 Fast Startup 恢复,机器自 09-13 22:40 起从未断电,整夜 Modern Standby。**合盖装包会持续耗电,留意**。此时间线同时解开同日 Sunshine 案之谜,见下方「跨案联动」。

## 根因(为何 WSL VM 永远活着)

`/etc/wsl.conf` systemd=true 之下:

1. **`Linger=yes`**——用户级 systemd 实例 7×24 运行
2. **docker.service + containerd 系统级 enabled 且 running**——09-11 已迁 rootless podman 的迁移遗留
3. podman-pause-*.scope 残留

三者使 VM 永不触发空闲退出 → 每次关机 WSLService 都有完整 VM 要拆 → 撞上其偶发挂死就是 +60s。

## 修复(2026-09-14 09:5x 全部执行并核验)

| # | 动作 | 核验 |
|---|---|---|
| 1 | `sudo systemctl disable --now docker docker.socket containerd`(rootless podman 不需要系统 docker) | 三者 `is-active` 全 `inactive`(执行时 docker.socket 的 "triggering units still active" 警告只是处理顺序,终态已核验) |
| 2 | `loginctl disable-linger $USER` | `Linger=no` |
| 3 | `~/.wslconfig`(Windows 侧)加 `vmIdleTimeout=60000` | 文件已含该行(用户自加,09:52) |
| 4 | `wsl --update` | 已是最新(2.7.14) |

残留:podman-pause scope ×1(会话/VM 退出后自灭,不影响关机)。预期效果:VM 空闲 60s 自退 → 关机时 WSLService 通常无事可做;即便偶发挂死,也少了"必然撞上"的暴露面。

## 待验证(下次自然关机,回归测试)

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=7011} -MaxEvents 5 | Format-List TimeCreated, Message
# 绿 = 不再出现新的 WSLService 超时行;1074 → 断电间隔 <15s
# 同时观察:"关机变睡眠"是否也消失(若仍在,另立新案查 Modern Standby 唤醒源)
```

## 跨案联动:解开同日 Sunshine 探测失败案

[sunshine-win11-output-device-fail](../2026-09-14-0936-sunshine-win11-output-device-fail/)的"00:27 服务启动 vs 08:59 tray 创建"之谜,由本案时间线解开:**当晚没有重启**——Sunshine 是在关机转换中途被拉起(转换把会话拆掉后滑入睡眠),encoder 探测失败于无会话状态;08:59 唤醒登录后 tray 才创建。原案假设 #1"无人登录时启动"方向正确、机制修正为"关机转换/睡眠状态"。已在原案 spec 追加修正段。

## 经验(可复用指纹)

- **关机慢先查 System 日志 7011/7009/7000**:30s 超时的消息体会直接点名服务,不用猜
- **WSL 关机慢二分法**:journal 时间戳(VM 侧)vs SCM 超时时间戳(Windows 侧)错开 = WSLService 服务端挂死;Ubuntu 无辜
- **linger + 遗留系统服务 = WSL VM 永不空闲**,永远站在关机关键路径上;迁 podman 后记得 `disable --now docker docker.socket containerd`
- **"关机变整夜睡眠"指纹**:无 6005/6006 + 无 Kernel-Boot 27 + Power-Troubleshooter 大跨度 Sleep→Wake
- Diagnostics-Performance 需管理员;非管理员取证可用 7011 + journal 对表替代

## 参考

- microsoft/WSL #8529(WSL 命令/关机挂 30s 同模式)、#939 无关;Power-Troubleshooter 1 / Kernel-Power 42/107 / Kernel-Boot 27 语义
- 迁移档案:[2026-09-11-2120-podman-wsl-ubuntu-native](../2026-09-11-2120-podman-wsl-ubuntu-native/)(rootless podman 迁移,docker.service 遗留源头)
- 同日晚间档案:[2026-09-13-2300-win11-usb-kb-mouse-wedge](../2026-09-13-2300-win11-usb-kb-mouse-wedge/)、[2026-09-13-2219-singbox-bilibili-dns-stall](../2026-09-13-2219-singbox-bilibili-dns-stall/)

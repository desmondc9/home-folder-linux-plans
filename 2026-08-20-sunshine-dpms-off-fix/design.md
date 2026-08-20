# Sunshine 熄屏后 Moonlight 无法连接 (RTSP 500 / Error 503)

日期: 2026-08-20
状态: 已修复 (fix A), fix B 经实验证伪后回退

## 背景

下午 15:00~17:00 用户带 iPad 出门,Kubuntu 笔记本留家。第一次 Moonlight(经 Tailscale/headscale)
连接 Sunshine 成功,之后所有重试失败:iPad 报 `connection failed, RTSP handshake failed with
error 500`,Android 报 `启动失败 Error 503`。回家点亮屏幕后立即恢复。

## 根因(日志实证)

**触发链: 闲置 30 分钟 → PowerDevil DPMS 关屏 → KMS 枚举不到显示器 → 流启动 Fatal → 500/503。**

时间线:

| 时间 | 事件 | 证据 |
|------|------|------|
| ~15:05 | 用户出门,首次 iPad 连接成功(屏幕还亮着) | 用户描述 |
| 15:16:52 | 无操作超时自动锁屏 | 1Password 日志 `Locked. Reason: Automatic(ScreenSaverActivated)` |
| 15:16:54 | kwin_wayland 意外重启 | user journal `The Wayland connection broke. Did the Wayland compositor die?` |
| 15:23:05 | iPad 重试触发旧 Sunshine 编码器探测 | sunshine journal |
| 15:23:48 | 旧 Sunshine (PID 488040) **SIGSEGV**(KMS 状态随 kwin 重启失效) | `coredumpctl list` |
| 15:24:01 | sunshine-watchdog(每分钟)自动重启 Sunshine,启动探测成功 | sunshine.log;锁屏不影响抓屏 |
| ~15:35 | PowerDevil `[AC][Display] TurnOffDisplayIdleTimeoutSec=1800` 触发 → 双屏 DPMS 断电 | powerdevilrc + 时序吻合(闲置起点 ~15:05) |
| 15:48/15:49/16:16/16:27 | 每次重试: `Error: Couldn't find monitor [0]` ×N → `Fatal: Unable to find display or encoder during startup` | sunshine.log |
| 19:58 | 回家点亮屏幕 → `CLIENT CONNECTED` ✓ | sunshine.log |

机制: 本机 Sunshine 2026.516 在 KWin Wayland 下只能走 KMS 抓屏(wlgrab 不可用: "Missing
Wayland wire for wlr-export-dmabuf"),`output_name = 0` 按序号抓第一个 KMS 显示器。双屏 DPMS
断电后 KMS 枚举为空 → 序号 0 不存在 → 启动即 Fatal。锁屏本身无害(15:24 锁屏状态下探测正常)。

## 复现验证(当晚实验)

21:18 手动 `kscreen-doctor --dpms off` 后从 iPad 发起 Moonlight 连接,**精确复现**了下午的现象
(`Couldn't find monitor [0]` → Fatal → 客户端 500)。屏幕回亮(用户输入)后同一秒内探测恢复
(`Found connector ID [140]`)。根因确认。

## 关键负结论: `global_prep_cmd` 救不了这个场景

曾尝试在 sunshine.conf 加 `global_prep_cmd` do 命令(连接时 `kscreen-doctor --dpms on` 唤醒屏幕),
实验证明无效,原因有二:

1. **顺序错误**: 客户端 launch 请求先触发编码器/显示器重探测,探测失败即 Fatal 中止,
   prep do-cmd 根本不会执行(日志: 21:19:00 探测失败 Fatal;21:19:07 显示器因用户输入恢复后,
   do-cmd 才在 21:19:07.562 "Executing Do Cmd" —— 在探测成功**之后**)。
2. **引号被吞**: Sunshine 的命令解析不吃 shell 引号,`bash -c '...'` 以 exit code 2 失败。
   以后若要用 prep cmd,应把逻辑放进脚本文件,do 只写脚本路径。

## 修复方案

### Fix A(已应用,根除)

`~/.config/powerdevilrc` `[AC][Display] TurnOffDisplayIdleTimeoutSec` 1800 → **0**(AC 下永不关屏),
`systemctl --user restart plasma-powerdevil.service` 生效,重启后值未被回写。

- 保留 `DimDisplayIdleTimeoutSec=900`(15 分钟降亮度,dim 只降背光,不影响抓帧)。
- 保留自动锁屏:锁屏状态抓屏正常,串流显示锁屏界面,可用 Moonlight 键盘输密码解锁。
- 注意: 只对 AC 电源模式改了;Battery 模式若插着电串流机的使用场景不涉及,未动。

### Fix B(已回退)

`global_prep_cmd` 方案证伪后已从 sunshine.conf 移除并重启服务,恢复干净配置
(`output_name = 0` / `upnp = enabled` / `vk_tune = 0`)。

## 残余风险与备注

- 若屏幕因**其他原因**断电(手动 `kscreen-doctor --dpms off`、Battery 模式默认超时、未来配置改动),
  远程连接仍会 500,需要人到场或在屏幕上产生输入。如需兜底,可扩展
  `~/.local/bin/sunshine-watchdog.sh`(已在跑,每分钟)加 "sunshine active 且 DPMS off 则唤醒"
  逻辑,代价是 Sunshine 运行时无法手动关屏 —— 暂未实施。
- 15:16:54 的 kwin_wayland 重启原因未追查(无 coredump);其导致的 Sunshine SIGSEGV 已被
  watchdog 覆盖(13 秒内自愈),暂不需处理。
- UPnP conflict 606 告警(与 192.168.31.100 即本机自身端口映射冲突)长期存在,与本次故障无关。

## 相关

- 脚本: `~/.local/bin/sunshine-display`(显示器切换)、`~/.local/bin/sunshine-watchdog.sh`
- 前一日档案: `~/plans/2026-08-19-sunshine-display-switch/`

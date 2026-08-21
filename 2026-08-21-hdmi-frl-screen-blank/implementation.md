# 实施记录: HDMI FRL 熄屏修复

日期: 2026-08-21 上午

## 任务清单

- [x] T1 证据收集: FRL 失败全量时间线(8/18 起)、kwin coredump 排查(无)、09:18 事件定性(用户注销非崩溃)、
      22:06 锁屏轮询实验复核(锁屏不关屏)
- [x] T2 Fix 1: `kscreen-doctor output.HDMI-A-1.mode.1` → HDMI-A-1 当前模式 3840x2160@60.00* ✓
- [x] T3 Fix 2: sunshine-watchdog.sh 增加 DPMS 自愈块(Sunshine active + 任一屏 off → dpms on);
      `bash -n` + 手动触发通过 ✓
- [x] T4 FRL 复发监控: persistent Monitor 盯 `journalctl -kf | grep "FRL link training failed"`(本 session 内有效)
- [x] T5 归档本文档 + 更新记忆

## 变更的文件

| 文件 | 变更 | 状态 |
|------|------|------|
| KWin 输出配置(经 kscreen-doctor 写入) | HDMI-A-1: 3840x2160@160 → @60 | 保留(修复) |
| `~/.local/bin/sunshine-watchdog.sh` | +DPMS 自愈块 | 保留(兜底) |

## 遗留观察项

- FRL 监控若报警 → 硬件层面(线材/接口),换认证 HDMI 2.1 线后可考虑回 4K@160
- 用户真实"离开即断连"场景建议下次出门前自然验证: 锁屏离开 10 分钟后从 iPad 连接应直接成功

## 8-21 下午验证与加固

- [x] T6 12:58 iPad 连接触发 Sunshine SIGSEGV(连接时探测崩溃,与 8-20 15:23 同款) → watchdog 自动重启(12:58:43)+ 强制亮屏(13:00:04),自愈链完整工作
- [x] T7 13:06 iPad 实测连接成功、画面正常、无探测报错 ✓
- [x] T8 watchdog 增强: 触发时 dump 每屏 DPMS 状态(区分 eDP-1/HDMI-A-1),并新增 DPMS 跳变秒级取证监控(找"谁在关屏")
- [ ] T9 关屏元凶待定位: 已排除 dim(≠DPMS off)/锁屏/合盖;下次无故关屏时取证监控会抓到案发时刻

## 演练验证 (13:10)

新增 `~/.local/bin/sunshine-drill.sh`(状态遍历实测: 基线/锁屏/手动熄屏+watchdog 救回/SIGKILL 崩溃恢复,每步强制 Sunshine 重探测判定)。首轮 6 PASS / 1 FAIL:

- S2a FAIL 是脚本竞态(dpms off 异步生效,2s 检查太早),非系统问题 —— watchdog 日志证明熄屏确实发生且在 ≤100s 内被救回;已修为轮询等待
- 演练期间用户 iPad 两次真实重连均 CLIENT CONNECTED ✓
- 已知残余窗口: 客户端恰好在熄屏~watchdog 救回(≤~70s)之间连接仍会 500,重试即可

## 事件驱动唤醒 daemon (13:27 上线)

用户提议的思路,替代/补充"防关屏": 只要有远程连接事件就点亮屏幕。

- `~/.local/bin/screen-wake-daemon.sh` + `screen-wake-httpd.py` + `~/.config/systemd/user/screen-wake-daemon.service`(已 enable)
- 触发源: ①Moonlight HTTPS/RTSP 入站连接(47984/47989/48010) ②SSH(22) ③`curl http://<主机>:47800/任意路径` 专用端点
- 轮询周期 2s,唤醒延迟实测 ≤1s;仅在屏幕确实 off 时动作,避免无意义 HDMI 重训练
- **踩坑记录**: ①ss 过滤要用 `sport`(本机是服务端,dport 是客户端临时端口) ②`state established` 会漏——Sunshine RTSP 对裸 TCP 秒拒(CLOSE-WAIT),须用 `state connected` ③zsh 无 /dev/tcp,测试用 nc
- E2E(13:27): 熄屏状态 iPad 发起连接 → daemon 1s 内点亮 → CLIENT CONNECTED,0 次探测失败 ✓
- HTTP 端点安全说明: 只亮屏不解锁,LAN/tailnet 暴露无副作用

## 最终架构落地 (13:32)

按用户要求,恢复所有"防关屏"设置,以事件驱动唤醒 daemon 作为唯一主防线:

- [x] T10 恢复 powerdevilrc: `TurnOffDisplayIdleTimeoutSec` 0 → **1800**(原始值),DimDisplay=900 保持;plasma-powerdevil 已重启且值未被回写
- [x] T11 恢复后安全网验证: screen-wake-daemon(active+enabled+47800 LISTEN)/watchdog.timer/Sunshine 全绿,脚本语法 OK
- [x] T12 保留 4K@60(不动 160Hz): FRL 警告仅出现在 dpms-on 链路重建时(驱动先试 FRL 失败回退 TMDS,良性);160Hz 下是使用中闪黑的元凶,daemon 无法覆盖"使用中"场景。恢复命令: `kscreen-doctor output.HDMI-A-1.mode.2`

最终分层(屏幕可自由熄灭,连接即唤醒):
1. 事件驱动(主): screen-wake-daemon 每 2s 盯 47984/47989/48010/22 入站连接,off → ≤1s 点亮;`:47800` HTTP 专用唤醒端点
2. 周期兜底(备): sunshine-watchdog 每分钟,进程崩溃重启 + 屏幕 off 强制点亮
3. 演练工具: sunshine-drill.sh 一键回归(基线/锁屏/熄屏救回/崩溃恢复)

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

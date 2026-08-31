# 实施记录 — HDMI 2.1 线缆验证 + 4K@120

执行日期:2026-08-24 11:19–11:25 CST,全部命令在会话内实测。

## 步骤

- [x] 现状采集:`kscreen-doctor -o`(外接 4K@60);connector→driver 映射(card1=nvidia 10DE:28A0,RTX 4060 Laptop,eDP+HDMI 同卡)。
- [x] EDID 解码:`edid-decode /sys/class/drm/card1-HDMI-A-1/edid` → HDMI Forum VSDB:FRL 12G/lane×4=48G、SCDC、DSC 1.2a、VIC 118。
- [x] 排除干扰:检查 `~/.local/bin/sunshine-watchdog.sh` 仅管 DPMS,无强制 60Hz 逻辑。
- [x] 切 4K@119.88:`kscreen-doctor output.HDMI-A-1.mode.6`,生效。
- [x] FRL 决定性压测:切 `mode.4`(4K@160)持续 60s,每 5s 采 `link status + dpms`,全程 connected/on 零断链(此频率为旧线闪黑点)。
- [x] 回落并定格 `mode.6`(4K@119.88),确认为当前模式。
- [x] 归档本目录并提交 ~/plans(公开仓库,内容无敏感信息)。

## 关键命令备忘

```bash
kscreen-doctor -o                                   # 查看模式(* 为当前)
kscreen-doctor output.HDMI-A-1.mode.6               # 4K@119.88(mode.4=160, mode.3=60)
edid-decode /sys/class/drm/card1-HDMI-A-1/edid      # HDMI 2.1 能力
cat /sys/class/drm/card1-HDMI-A-1/status            # 链路状态
journalctl -k --since '-5 min'                      # nvidia 模式切换通常无日志,故障检测靠 status+dpms 轮询
```

## 回退

```bash
kscreen-doctor output.HDMI-A-1.mode.3   # 回 4K@60(8-21 起的旧规避配置)
```

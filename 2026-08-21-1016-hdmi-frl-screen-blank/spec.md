# 使用中无征兆熄屏 + 离开后 Sunshine 断连:HDMI FRL 链路训练失败

日期: 2026-08-21
状态: 已修复(降 4K@60 + watchdog 自愈),FRL 复发监控运行中

## 背景

用户报告(在 2026-08-20 修改 powerdevilrc 之后):

1. Kubuntu **正在使用时**会时不时无征兆熄屏
2. 离开电脑后仍会"自动熄屏",导致 Sunshine + Moonlight 无法连接

## 根因(日志实证)

### 问题 1: HDMI FRL link training failed —— 与 powerdevilrc 无关(时间上巧合)

- 外接小米显示器跑在 **3840x2160@160Hz**,4K@160 必须走 HDMI 2.1 FRL(Fixed Rate Link)链路
- `nvidia-modeset: WARNING: GPU:0: HDMI FRL link training failed` 全量记录:
  **8/18 ×2、8/19 ×2、8/20 ×4、8/21 ×2** —— 8/18 起每天都在发生,远早于 powerdevilrc 修改
- 每次 FRL 训练失败 → 链路重训练 → 外屏闪黑;KWin 重枚举输出时内屏可能跟着闪 →
  表现为"使用中无征兆熄屏"
- 佐证: 8/20 21:56:54 Sunshine `Couldn't find monitor [0]`,21:57:01 powerdevil
  `Udev event detected` + i2c EDID 重读 = 一次链路事件导致 KMS 枚举瞬时空

### 问题 2: 两个原因叠加

- 8/20 下午的离开断连 = PowerDevil AC 闲置 30 分钟 DPMS 关屏 →
  **已于 8/20 晚修复**(`TurnOffDisplayIdleTimeoutSec=0`,8/21 晨复查配置仍在)
- 8/20 21:56 的断连 = 上述 FRL 链路事件,不是闲置关屏
- 8/20 22:06-22:08 实验: 锁屏状态 90 秒轮询双屏始终 on → 锁屏不关屏、fix 生效

### 排除项

- kwin 从未留下 coredump;8/21 09:18 的 "Wayland connection broke" 是用户主动注销
  (org.kde.Shutdown 日志),非崩溃
- 8/21 09:10 kaccess/xembedsniproxy/gmenudbusmenuproxy SIGABRT、09:15 WeChat 三连崩 =
  09:08 重启后的会话启动竞态,与本问题无关
- 锁屏 greeter 的 `SessionManagementScreen.qml:160 TypeError` 为无害 QML 告警

## 修复

### Fix 1: HDMI-A-1 降到 4K@60(根除 FRL)

```
kscreen-doctor output.HDMI-A-1.mode.1   # 3840x2160@60,HDMI 2.0 TMDS,不走 FRL
```

- 已生效并持久化(kscreen-doctor 会写入 KWin 输出配置)
- 代价: 外接屏刷新率 160→60Hz;串流不受影响(Sunshine 抓的是内屏 eDP-1)
- 若以后要回 160Hz: 换 HDMI 2.1 Ultra High Speed 认证线再试(FRL 失败多为线材信号完整性不足)
- eDP-1 内屏 240Hz 不动(eDP 不走 FRL,与本问题无关)

### Fix 2: sunshine-watchdog 增加屏幕自愈(兜底)

`~/.local/bin/sunshine-watchdog.sh`(每分钟由 systemd user timer 触发)在端口探活之外新增:

- 条件: Sunshine 服务 active 且 `kscreen-doctor --dpms show` 任一屏幕为 off
- 动作: `kscreen-doctor --dpms on` 强制通电
- 代价: Sunshine 运行期间无法手动关屏(要关屏先停 Sunshine)

## 验证

- 4K@60: `kscreen-doctor -o` 显示 HDMI-A-1 当前模式 `3840x2160@60.00*` ✓
- watchdog: `bash -n` 语法检查 + 手动 `systemctl --user start sunshine-watchdog.service` 通过 ✓
- FRL 复发监控: `journalctl -kf | grep "FRL link training failed"` 常驻监控已挂
  (4K@60 后预期为零;若复发说明线材/接口硬件问题,需换线)

## 相关档案

- ~/plans/2026-08-20-2127-sunshine-dpms-off-fix/(前一日 DPMS 关屏事故,本事故的另一半)

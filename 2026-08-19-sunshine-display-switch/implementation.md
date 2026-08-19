# Sunshine 串流显示器切换脚本 — 实施记录

日期: 2026-08-19

## 任务清单

- [x] 勘察: Sunshine 服务形态(flatpak 用户服务)、配置位置、KMS 捕获后端、双屏 connector 归属
- [x] 实测坑 1: `output_name = eDP-1`(名字) → `Couldn't find monitor [553171]`,编码器全部探测失败
- [x] 实测坑 2: "Monitor N is ..." 列表顺序重启后翻转(00:26 时 0=HDMI,16:24 时 0=eDP)
- [x] 用 `/sys/class/drm/card1-*/connector_id` 拿到 eDP-1=140 / HDMI-A-1=137
- [x] 实测映射: `output_name=0` → connector 140 (eDP-1); `output_name=1` → connector 137 (HDMI-A-1)
- [x] 编写 `~/.local/bin/sunshine-display`(0/1/toggle/status + 切换后核对 connector + 限流重试)
- [x] 端到端测试: `toggle` → eDP-1 ✓(connector 140 核对通过); 再 `toggle` → HDMI-A-1 ✓(connector 137)
- [x] 触发并修复 systemd 限流; 脚本内加入 `reset-failed` + 10s 重试
- [x] 恢复用户原配置 `output_name = 0` 并确认服务 active、捕获 connector 140

## 变更文件

- 新增: `~/.local/bin/sunshine-display` (bash, 可执行, `~/.local/bin` 已在 PATH)
- 修改: `~/.config/sunshine/sunshine.conf` 的 `output_name`(最终恢复为 0)

## 远程使用

```bash
ssh -p 6000 desmond@laptop.signal-align.com
sunshine-display          # 看当前
sunshine-display 1        # 切到小米外接屏
sunshine-display toggle   # 来回切
```

切换后 Moonlight 客户端需要重新连接。

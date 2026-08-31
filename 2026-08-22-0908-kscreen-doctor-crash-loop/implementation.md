# 实施记录: screen-wake-daemon kscreen-doctor 崩溃循环修复

日期: 2026-08-22

## 任务清单

- [x] T1 定位根因: coredumpctl(20+ SIGABRT,cgroup=screen-wake-daemon.service)+ apport ProcEnviron(无 DISPLAY/WAYLAND_DISPLAY)+ 时间线(08:53:56 unit 启动 < 08:54:32 会话就绪)→ 开机竞态
- [x] T2 复现验证: daemon 最小环境跑 `kscreen-doctor --dpms show` → EXIT 134 (SIGABRT);补显示环境 → EXIT 0
- [x] T3 Fix A: unit 加 `Wants=graphical-session.target`,`WantedBy` default.target → graphical-session.target
- [x] T4 Fix B: 脚本加 `ensure_display_env()`(manager 补抓 + 抓不到本轮跳过),httpd 拉起前先调用
- [x] T5 应用: `daemon-reload` + `reenable`(symlink 确认迁到 graphical-session.target.wants)+ restart
- [x] T6 验证:
  - 新 daemon (/proc/13259/environ)含 DISPLAY/WAYLAND_DISPLAY/XAUTHORITY ✓
  - 用 daemon 完整环境跑 `--dpms show` → EXIT 0 ✓
  - 重启后 daemon cgroup 零新崩溃(之后仅有的两个 coredump 均属 konsole,为排查期自己的测试)✓
  - Fix B 自愈模拟: `env -i` 干净环境(无显示变量)source 函数 → 从 manager 导入 → kscreen-doctor OK ✓
- [x] T7 归档本文档 + spec.md

## 变更的文件

| 文件 | 变更 | 备份 |
|------|------|------|
| `~/.config/systemd/user/screen-wake-daemon.service` | +`Wants=graphical-session.target`;`WantedBy` default.target → graphical-session.target | `.bak-20260822` |
| `~/.local/bin/screen-wake-daemon.sh` | +`ensure_display_env()`;`wake_if_off` 与 httpd 拉起前调用 | `.bak-20260822` |

未变更: sunshine-watchdog.service/timer(无此竞态,见 spec.md)。

## 验证方式

```bash
# 1. daemon 环境
tr '\0' '\n' < /proc/$(systemctl --user show screen-wake-daemon.service -p MainPID --value)/environ \
  | rg '^(DISPLAY|WAYLAND_DISPLAY|XAUTHORITY)='

# 2. 最小复现(修复前必崩 134 / 修复后 0)
env -i PATH=/usr/bin:/bin XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0 \
    WAYLAND_DISPLAY=wayland-0 XAUTHORITY=/run/user/1000/xauth_TcCvNP \
    LANG=en_US.UTF-8 kscreen-doctor --dpms show

# 3. 崩溃计数(重启后应为零新增)
coredumpctl list --no-pager | rg kscreen-doctor

# 4. 依赖图
systemctl --user show screen-wake-daemon.service -p Wants -p WantedBy -p After
```

## 待办 / 后续

- 下次真实开机后观察一次(尤其 frp 重连触发轮询时)确认无崩溃 — 结构性修复,预期零崩溃。
- 可选清理: `sudo rm /var/crash/_usr_bin_kscreen-doctor.1000.crash`;旧 coredump 由 systemd 自动轮转。

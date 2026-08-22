# screen-wake-daemon 开机后 kscreen-doctor 崩溃循环 (SIGABRT ×20+)

日期: 2026-08-22
状态: 已修复(unit 排序 + 脚本环境守卫),验证通过

## 背景

早上开机后(08:56:09–08:56:50)kscreen-doctor 以 SIGABRT 连续崩溃 20+ 次(约每 2s 一次),
drkonqi/apport 各报一次。kscreen-doctor 在桌面 shell 里手动运行完全正常,但崩溃循环周期性出现。

## 根因(证据链)

**触发链: 开机早期 user unit 启动 → 图形会话尚未导入显示环境 → kscreen-doctor 无
DISPLAY/WAYLAND_DISPLAY → Qt 找不到 display → qFatal → SIGABRT。**

`screen-wake-daemon.service` 每 2s 轮询入站连接(Sunshine/SSH),有连接就调用
`kscreen-doctor --dpms show`。开机后 frp SSH 隧道重连 → 轮询命中 → 每次调用都崩溃。
崩溃进程环境(`/proc/PID/environ` + apport `ProcEnviron`)只有 `LANG/PATH/SHELL/XDG_RUNTIME_DIR`,
**没有 DISPLAY / WAYLAND_DISPLAY / XAUTHORITY**。

时间线:

| 时间 | 事件 | 证据 |
|------|------|------|
| 08:53:43 | 开机 | `uptime -s` |
| 08:53:56 | screen-wake-daemon.service 启动(开机后 13s) | `ActiveEnterTimestamp` |
| 08:54:32 | graphical-session.target 就绪,Plasma 此后才把 DISPLAY/WAYLAND_DISPLAY 导入 systemd user manager | journal `Reached target graphical-session.target` |
| 08:56:09–08:56:50 | frp SSH 隧道重连 → daemon 每 2s 轮询命中 → `kscreen-doctor --dpms show` SIGABRT ×20+ | `coredumpctl list`(全部 cgroup = screen-wake-daemon.service) |
| 09:00:48 / 09:02:43 | 两次额外崩溃,均来自 konsole —— 排查期的故意复现/测试 | coredump `Control Group: app-org.kde.konsole...scope` |

**为什么 `After=graphical-session.target` 没拦住**: unit 只有 `After=` 而没有 `Wants=` 把 target
拉进同一启动事务,且 `WantedBy=default.target`。开机事务执行时 graphical-session.target 尚未
激活、也不在事务内,ordering 被跳过 —— systemd 经典陷阱。daemon 进程永远不退出(while 循环),
`Restart=always` 也无从触发,坏环境在整个会话期间一直残留。

**后果不止是崩溃噪音**: `kscreen-doctor --dpms show` 一崩,`|| return 0` 静默跳过 → 屏幕不唤醒
—— 正是这个 daemon 要消灭的"DPMS 关屏 = 串流必死"故障模式。昨天 13:27 的 E2E 通过,是因为
当时是会话中手动重启(继承了已导入的环境);今天是第一次开机自启,竞态首次暴露。

## 复现验证

```bash
# 用 daemon 的最小环境复现: EXIT 134 (SIGABRT)
env -i PATH=/usr/bin:/bin XDG_RUNTIME_DIR=/run/user/1000 LANG=en_US.UTF-8 \
    SHELL=/usr/bin/zsh kscreen-doctor --dpms show
# → qt.qpa.xcb: could not connect to display → abort

# 补上显示环境后: EXIT 0
env -i PATH=/usr/bin:/bin XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0 \
    WAYLAND_DISPLAY=wayland-0 XAUTHORITY=... LANG=en_US.UTF-8 \
    kscreen-doctor --dpms show
# → dpms mode for screen HDMI-A-1: on / eDP-1: on
```

## 修复方案

- **Fix A(根因)**: unit 增加 `Wants=graphical-session.target`,`WantedBy` 从 default.target 改为
  graphical-session.target。Wants= 把 target 拉进同一事务,After= 才真正生效;会话就绪时启动,
  显示环境已导入,进程天然继承。
- **Fix B(兜底,纵深防御)**: 脚本新增 `ensure_display_env()` —— DISPLAY/WAYLAND_DISPLAY 缺失时
  从 user manager 补抓(`systemctl --user show-environment`),抓不到就本轮跳过,2s 后轮询重试;
  httpd 子进程拉起前先补抓一次,让子进程也继承正确环境。

未改动 sunshine-watchdog.service:`OnBootSec=3min` 首跑时会话早已就绪,且 oneshot 每次触发
都重新继承管理器当前环境,天然自愈,无此竞态。

## 关键负结论 / 经验

- systemd user unit 若要调用 GUI 工具(kscreen-doctor 等),必须 `Wants=` + `WantedBy=` graphical-
  session.target 三件套;只写 `After=` 且 WantedBy=default.target 时 ordering 在开机事务中被跳过。
- 排查期两次"假崩溃"来自自己的测试命令(konsole cgroup) —— coredump 的 Control Group 字段是
  区分崩溃来源的第一证据,别只看二进制名。

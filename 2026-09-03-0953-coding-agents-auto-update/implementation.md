# 实施记录 — coding agents 每日自动更新

## 任务

- [x] 核实四工具更新命令与本机安装(claude / opencode upgrade / kimi upgrade / pi update --extensions)
- [x] 编写更新脚本 + systemd user service/timer
- [x] enable --now 并手动触发验收

## 反馈回路

- `systemctl --user list-timers coding-agents-update.timer`(下次触发时间)
- `journalctl --user -u coding-agents-update.service`(每工具 before/after 版本对照行)

## 步骤与结果

1. 环境核实:claude→~/.local/share/claude/versions(自管 shim),`opencode upgrade` 存在,
   `kimi upgrade|update` 无 --yes 参数,`pi update` 支持 --extensions;时区 Asia/Shanghai;
   user unit 目录无既有 timer 冲突(仅系统级 launchpadlib-cache-clean)。
2. 写 `~/.local/bin/update-coding-agents.sh`:四工具顺序执行,单工具 timeout 600(kimi 回退分支 900),
   失败隔离;kimi 双路径(`yes | kimi upgrade` → 官方 install.sh 回退);PATH 显式注入 nvm 与 ~/.local/bin。
3. service(oneshot) + timer(OnCalendar=*-*-* 04:00:00, Persistent=true) → chmod 644 → daemon-reload →
   enable --now;list-timers 确认 NEXT = 2026-09-04 04:00:00 CST。
4. 验收:`systemctl --user start coding-agents-update.service` → exit 0,耗时约 15s(23s CPU):
   - claude 2.1.258 → **2.1.259 CHANGED**(真实升级)
   - opencode 1.18.27 unchanged(cmd ok)
   - kimi 0.40.1 unchanged(upgrade 路径 ok,无平台误判;"yes: Broken pipe" 为管道正常噪音)
   - pi 0.84.4 unchanged(cmd ok,非交互无阻塞)

## 证据留存

- list-timers: `Fri 2026-09-04 04:00:00 CST coding-agents-update.timer`
- journal: `===== run end =====` + systemd `Finished coding-agents-update.service (Consumed 23.281s CPU)`
- 日志文件首条完整运行记录:`~/.local/state/coding-agents-update.log`

## 清理

- `/tmp/cua-*.out` 为脚本每次运行的自覆盖产物,无需清理;无 repo 变更。

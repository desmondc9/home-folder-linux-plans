# Coding agents 每日自动更新(claude/opencode/kimi/pi)

- 日期: 2026-09-03
- 环境:Kubuntu 26.04 + Wayland 笔记本(yaoshi15pro)
- 状态: 已完成并验证(当日手动触发实测:claude 2.1.258→2.1.259 真实升级)

## 背景与目标

四个 coding agent CLI 各有自更新机制,手工维护易漏。目标:每日 04:00 (Asia/Shanghai) 自动更新
claude / opencode / kimi code / pi,单工具失败不影响其余,留痕可查。

## 关键决策与理由

| 决策 | 理由 |
|---|---|
| systemd user timer(非 openclaw cron) | 纯 shell 任务无需 agent 智能;Persistent=true 使关机错过 04:00 后开机补跑 |
| 各工具原生 updater + kimi 双路径 | claude update / opencode upgrade / pi update --extensions 为原生命令;kimi upgrade 在 0.9.0 会误判平台不支持,脚本先试 `yes \| kimi upgrade`(0.40.1 实测已正常),失败回退官方 install.sh |
| `yes \|` 喂 kimi 的交互确认 | owner 明确指出 kimi upgrade 有确认提示;防御性保留(0.40.1 实测已非阻塞) |
| 绝对路径 + 显式 PATH | systemd user 环境 PATH 极简,nvm / ~/.local/bin 不在默认路径 |
| 日志双通道 | stdout 进 journald + 追加 ~/.local/state/coding-agents-update.log(含 before/after 版本对照) |

## 最终配置快照

```
~/.local/bin/update-coding-agents.sh                 # 755 更新脚本(四工具顺序执行,失败隔离)
~/.config/systemd/user/coding-agents-update.service  # Type=oneshot
~/.config/systemd/user/coding-agents-update.timer    # OnCalendar=*-*-* 04:00:00, Persistent=true
日志: journalctl --user -u coding-agents-update.service ; ~/.local/state/coding-agents-update.log
```

## 排障知识点(复用价值)

- `kimi upgrade` 0.9.0 在 linux 误判 "native (windows)" 不支持自更新;0.40.1 已正常——老版本跑此命令
  会失败,这正是脚本带官方 install.sh 回退分支的原因(观察日志 fallback 是否触发可判版本行为变化)。
- `pi update --extensions` 非交互无提示,直接可用(无需 --approve)。
- systemd 服务里 `yes |` 管道在目标进程退出后 yes 收 SIGPIPE,journal 的 "Broken pipe" 属正常噪音。
- claude 的稳定入口是 ~/.local/bin/claude(指向 versions/<ver> 的 shim),脚本用 command -v 解析。

## 验收标准(已满足)

- timer enabled;list-timers 显示下次 2026-09-04 04:00 CST
- 手动触发 service:exit 0;claude 2.1.258→2.1.259 真实升级;opencode 1.18.27 / kimi 0.40.1 /
  pi 0.84.4 均 cmd ok(已是最新)

## Follow-ups

- 若某日日志出现 kimi fallback 分支被触发,说明 kimi 升级行为又变了,需复核。

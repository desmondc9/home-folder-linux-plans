# Claude Code 彻底卸载(指令迁移至 opencode AGENTS.md)

日期: 2026-11-14 · 状态: 已完成 · 实施记录: [implementation.md](implementation.md)
- 前置任务: [2026-11-14-1148-opencode-sudo-revocation](../2026-11-14-1148-opencode-sudo-revocation/)(同日 AI 会话权限加固)

## 背景与决策

用户确认 Claude Code 已不再使用,要求彻底删除 `~/.claude/`。排查发现实际痕迹远不止该目录,且存在两个**直接删除会出问题的依赖**:

1. **`~/.config/opencode/AGENTS.md` 是指向 `~/.claude/CLAUDE.md` 的软链** —— 直接删除会使 opencode 全局指令(整套开发工作流 playbook,47KB,当天 11:47 仍在活跃维护)变成死链,所有未来 opencode 会话丢失指令。
2. **`coding-agents-update.timer`**(每周日 04:00,下次 2026-11-15 04:00)调用 `~/.local/bin/update-coding-agents.sh` 更新 claude/opencode/kimi/pi —— 但脚本对 claude 的处理是 `command -v claude` 为空即跳过(`NOT_FOUND, skip`),删除二进制后无需改脚本,opencode/kimi/pi 更新不受影响。

**决策**:先备份小体量数据 → AGENTS.md 软链转实体文件(指令保留) → 删除全部 claude 痕迹(含 12G 版本目录) → 更新脚本零改动(自跳过)。

## 清除范围

| 路径 | 内容 | 大小 |
|---|---|---|
| `~/.claude/` | CLAUDE.md、settings.json、history、sessions、projects、skills、plugins | 8.9M |
| `~/.claude.json` | 根配置(含 OAuth 凭据,0600) | 37K |
| `~/.local/bin/claude` | 软链 → versions/2.1.323 | - |
| `~/.local/share/claude/` | 原生安装器多版本堆积 | **12G** |
| `~/.cache/claude`、`~/.cache/claude-cli-nodejs` | 缓存 | - |
| `~/.local/state/claude/` | 状态 | - |

## 保留 / 迁移

- **`~/.config/opencode/AGENTS.md`**:软链 → 实体文件(47473 字节,与删除前 CLAUDE.md 逐字节一致),opencode 会话继续加载同一套工作流指令。
- **`update-coding-agents.sh`**:零改动,明早起日志 `claude: NOT_FOUND, skip`,继续更新 opencode/kimi/pi。
- **`~/.zshrc` 第 128–210 行 ccw wrapper**:全部为注释行(早已停用),未动;无功能影响。

## 回退

- 配置/历史备份:`~/Backups/claude-code-removal-2026-11-14/`(`dot-claude/`、`claude.json`、`state-claude/`,共 8.9M;12G 程序本体未备份,可重装)。
- 重装 Claude Code 后将 `dot-claude/` 恢复为 `~/.claude/`、`claude.json` 恢复为 `~/.claude.json` 即可;如需恢复软链形态:`ln -sf ~/.claude/CLAUDE.md ~/.config/opencode/AGENTS.md`。

## 后续变更(2026-11-14)

- **11:55 停用**:应用户要求 `systemctl --user disable --now coding-agents-update.timer`,停止且不再随登录/开机启用,opencode/kimi/pi 转为手动更新。
- **11:57 彻底删除**:应用户要求,unit 文件(`coding-agents-update.{service,timer}`)、脚本 `~/.local/bin/update-coding-agents.sh`、日志 `~/.local/state/coding-agents-update.log`(36K,含末次 04:00 运行记录)全部删除;`daemon-reload` + `reset-failed` 后 systemd 无任何 coding 残留条目(status 报 `could not be found`)。zshrc / crontab / `/tmp/cua-*.out` 均无引用或残留。
- 备份:`~/Backups/coding-agents-update-removal-2026-11-14/`(unit ×2 + 脚本 + 日志);恢复 = 还原三处文件后 `systemctl --user daemon-reload && systemctl --user enable --now coding-agents-update.timer`。

## 验收标准

- [x] 7 处 claude 路径全部 `No such file or directory`;`command -v claude` 为空
- [x] AGENTS.md 为实体文件(`-rw-rw-r--`,47473 字节),内容与删除前一致
- [x] 用更新脚本同款 PATH 模拟检测:输出 `claude NOT_FOUND, skip`,定时器不会重建
- [x] 磁盘回收:根分区占用降至 55G(可用 95G,回收约 12G)

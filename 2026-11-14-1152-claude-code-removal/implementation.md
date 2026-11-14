# 实施记录:Claude Code 彻底卸载

执行时间: 2026-11-14 11:52 · 主机: brave-goose-1 · 操作者: opencode 会话(经用户确认)

## 1. 排查(只读)

| 检查 | 结果 |
|---|---|
| `ls -la ~/.claude/` + `du -sh` | 8.9M:CLAUDE.md(47K,当天 11:47 更新)/ settings / history / sessions / projects / skills / plugins |
| `ls -la ~/.config/opencode/AGENTS.md` | **软链 → `~/.claude/CLAUDE.md`**(2026-09-02 建立) |
| `~/.local/bin/claude` | 软链 → `~/.local/share/claude/versions/2.1.323` |
| `du -sh ~/.local/share/claude` | **12G**(原生安装器版本堆积) |
| `coding-agents-update.service/.timer` | oneshot + 周日 04:00,执行 `update-coding-agents.sh`(claude 段:command -v 为空 → skip) |
| `rg claude ~/.zshrc` | 仅第 128–210 行 ccw wrapper,全部注释行 |
| `npm ls -g` | 无 claude 包(纯原生安装) |

## 2. 执行顺序(顺序敏感:先备份、先转实体文件,再删)

```bash
# ① 备份小体量数据(程序本体 12G 可重装,不备份)
BK="$HOME/Backups/claude-code-removal-2026-11-14"
mkdir -p "$BK"
cp -a ~/.claude "$BK/dot-claude"
cp -a ~/.claude.json "$BK/claude.json"
cp -a ~/.local/state/claude "$BK/state-claude"

# ② AGENTS.md 软链 → 实体文件(cp -L 跟随软链落盘,再原子替换)
cp -L ~/.config/opencode/AGENTS.md ~/.config/opencode/AGENTS.md.real \
  && mv ~/.config/opencode/AGENTS.md.real ~/.config/opencode/AGENTS.md

# ③ 全量删除
rm ~/.local/bin/claude
rm -rf ~/.local/share/claude ~/.cache/claude ~/.cache/claude-cli-nodejs \
       ~/.local/state/claude ~/.claude ~/.claude.json
```

## 3. 验证

| 验证 | 结果 |
|---|---|
| `ls -d` 7 处路径 | 全部 `No such file or directory` ✅ |
| `command -v claude` | 空 ✅ |
| 用脚本同款 PATH 模拟 `command -v claude` | `claude NOT_FOUND, skip` —— 明早 04:00 定时器安全 ✅ |
| `ls -la ~/.config/opencode/AGENTS.md` | 实体文件 47473 字节,内容完好 ✅ |
| `df -h /` | 可用 95G(回收 ~12G)✅ |

## 4. 备注

- 本会话的指令原本加载自 `~/.claude/CLAUDE.md`,删除后 harness 已卸载该指令集;内容完整保存于 `~/.config/opencode/AGENTS.md`,后续新会话照常加载。
- `update-coding-agents.sh` 零改动:claude 段自跳过,opencode/kimi/pi 更新不受影响(最小变更原则,避免改脚本引入凌晨定时任务故障)。
- 后续(同日 11:55):`systemctl --user disable --now coding-agents-update.timer` —— 应用户要求停止自动更新;已验证 `inactive` + `disabled`,timer 列表无条目。恢复:`systemctl --user enable --now coding-agents-update.timer`。
- 后续(同日 11:57):定时任务与脚本彻底删除 —— 备份至 `~/Backups/coding-agents-update-removal-2026-11-14/`(unit ×2 + 脚本 + 36K 日志)后删除原文件,`daemon-reload` + `reset-failed`;验证 `list-unit-files` 无 coding 条目、timer status `could not be found`、4 个路径全部不存在。zshrc / crontab / `/tmp/cua-*.out` 均无引用或残留。
- `~/.claude.json`(OAuth 凭据,0600)已随备份保存;若确定永不回退,可择日清除 `~/Backups/claude-code-removal-2026-11-14/`。

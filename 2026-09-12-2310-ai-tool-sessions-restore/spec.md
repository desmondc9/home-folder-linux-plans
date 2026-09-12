# claude code / kimi(code) / pi / cursor 历史 session 从 restic 快照补全恢复

- 日期:2026-09-12 23:10
- 环境:WSL2 Ubuntu 26.04 @ Win11 物理机 DESKTOP-J7NBNU4(目标);数据来源为笔记本快照 `00ae3b7e`(2026-09-11 14:54)
- 状态:已完成,union 合并(--overwrite never),本机已有文件零覆盖

## 1. 背景与检查结论

继 [opencode-session-restore](../2026-09-12-2247-opencode-session-restore/) 之后,检查其余 AI 工具目录在本 WSL 的完整性:

| 目录 | 恢复前 | 恢复后 | 缺口内容 |
|---|---|---|---|
| `~/.kimi` | 无 | 218M / 35 sessions | 整目录(kimi CLI) |
| `~/.kimi-code` | 无 | 479M / 34 sessions | 整目录(kimicode) |
| `~/.pi` | 仅 skills(12K) | 1.7M(agent 完整:sessions/auth/settings/mcp) | `~/.pi/agent` 主体 |
| `~/.claude.json`(+2 备份) | 无 | 232K | 登录/状态文件 |
| `~/.claude` | 640M / 8,068 文件 | 640M(+零散补齐) | 基本完整(9/11 选择性恢复已含大头) |
| `~/.cursor` | 1.4G / 3,198 文件 | 1.4G(+chats 等) | 基本完整 |

实际缺口共 8,217 个文件 / 684 MiB(≈ .kimi 210M + .kimi-code 472M + .pi + .claude.json*)。

## 2. 方法:union 合并恢复(可复用模式)

```bash
wsl.exe -u root -- bash -c 'source /root/restic-env && restic restore 00ae3b7e --target / \
  --overwrite never \
  --include "/home/desmond/.kimi" --include "/home/desmond/.kimi/**" \
  --include "/home/desmond/.kimi-code" --include "/home/desmond/.kimi-code/**" \
  --include "/home/desmond/.pi" --include "/home/desmond/.pi/**" \
  --include "/home/desmond/.claude" --include "/home/desmond/.claude/**" \
  --include "/home/desmond/.claude.json" ... ; \
  chown -R desmond:desmond ~/.kimi ~/.kimi-code ~/.pi ~/.claude ~/.cursor ...'
```

- `--overwrite never` = 只写本机不存在的文件,本机 WSL 时期新数据(如 `.claude/history.jsonl` 增量)绝不回退。先 `--dry-run` 确认缺口(8,217/684MiB)再实跑,9 秒完成
- 新文件以 root 落盘,`chown -R desmond:desmond` 归位
- 免 staging:`--target /` + 精确 `--include` 直接落位,不经 /tmp(tmpfs 是内存,21G 级数据别走 tmpfs)

## 3. 经验教训

- **`restic ls --json <dir>` 的目录过滤在 0.18.0 上不可靠**:输出整棵快照树;循环调用 8 次后拼接统计,所有计数/体积虚增 8 倍(误判缺口 21G,实际 684MiB)。**容量判断以 `restic restore --dry-run` 的 Summary 为准**,ls 统计仅作参考
- union 合并三要素:`--overwrite never`(保新)+ 精确 `--include`(保界)+ root 落盘后 `chown`(保属主)
- 恢复的登录态文件(`.claude.json`、`.pi/agent/auth.json`)可能因机器指纹不同要求重新登录,属预期

## 4. 性能与容量

- 恢复量 684MiB(实测),来源 Azure East Asia;本机磁盘 895G 可用,无压力
- 新增数据落在每日 restic 备份范围内(AI 工具目录一律保留),当晚 03:00 自动纳入增量

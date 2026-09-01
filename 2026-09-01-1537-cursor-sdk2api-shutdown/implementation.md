# cursor-sdk2api 下线 — 实施记录

执行时间:2026-09-01 15:59–16:05 CST。brainstorming(bounded 路径)→ 用户批准设计 → 执行。

## 步骤与结果

| # | 动作 | 结果 |
|---|------|------|
| 0 | 备份 `~/.zshrc` → `/tmp/zshrc.bak-cursor-sdk2api-*` | ✅ |
| 1 | `systemctl --user disable --now cursor-sdk2api.service` | ✅ wants 符号链接移除;`is-active`=inactive,`is-enabled`=disabled |
| 2 | `rm` unit 文件 + `daemon-reload` + `reset-failed` | ✅ `status` 报 "Unit cursor-sdk2api.service could not be found" |
| 3 | `rm -rf ~/.config/cursor-sdk2api`(gateway.env,含 `csk_***` 网关密钥) | ✅ 路径不存在 |
| 4 | `rm -rf ~/.local/share/cursor-sdk2api`(22MB:auths 账号池/sdk-store/lineage/trace) | ✅ 路径不存在(不可逆,用户已确认不备份) |
| 5 | `git worktree remove --force .worktrees/2026-09-01-0240-cursor-sdk2api-aca-deploy` + `git branch -D feature/cursor-sdk2api-aca-deploy` + `git prune` | ✅ 分支删于 1e18349(=main,零丢失);worktree 列表只剩主检出;ACA spec 随之废弃 |
| 6 | `~/.zshrc` 三处编辑:①头注释 provider 列表去 `cursor-sdk2api` ②删 `cursor-sdk2api)` case 分支(含 `csk_***` token 行)③unknown-provider 提示同步 | ✅ 三处 Edit 全部命中 |

## 验证证据

```
$ zsh -n ~/.zshrc            → SYNTAX OK
$ rg sdk2api ~/.zshrc        → (none)
$ ss -ltn | grep :8080       → (8080 free)
$ systemctl --user status cursor-sdk2api → could not be found
$ zsh -ic 'ccw --provider=cursor-sdk2api'
  ccw: unknown provider 'cursor-sdk2api' (expected: kimi, glm, minimax, deepseek, cursorbridge)
  exit=2
```

cursorbridge.dev 实测(验收用 1-token 最小请求,token 取自 `~/.zshrc` cursorbridge 分支):

- 直连:`curl: (28) Operation timed out after 25002ms`,HTTP 000 —— **GFW 拦 Cloudflare 域,预期内**
- 走 `127.0.0.1:10809`:`HTTP 200`,响应 `{"content":[{"text":"Hi",...}],"model":"default","stop_reason":"end_turn"}` ✅

## 遗留事项

- **每次用 `ccw --provider=cursorbridge` 前确保 shell 已 export 代理**(直连实测超时;`.zshrc` 代理导出默认是注释状态)。
- 想恢复本地网关:见 spec.md §5 恢复路径。
- 两个 repo clone(上游 176MB + fork 174MB)按用户决定保留在 `~/Repos/`;将来确认不再回头可手动删除释放 350MB。
- `/tmp/zshrc.bak-cursor-sdk2api-*` 备份随 /tmp 清理自然过期。

## 性能与容量

Step G 不触发(纯服务下线 + shell 配置变更,理由见 spec.md §6)。

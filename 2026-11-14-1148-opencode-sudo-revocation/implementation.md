# 实施记录:opencode sudo 取消 + openclaw 免密残留清除

执行时间: 2026-11-14 11:4x · 主机: brave-goose-1 · 操作者: opencode 会话(经用户确认)

## 1. 诊断(只读)

| 检查 | 结果 |
|---|---|
| `sudo -n -l` | `(ALL:ALL) ALL` + `(ALL:ALL) NOPASSWD: ALL` |
| `sudo -n grep -rn NOPASSWD /etc/sudoers /etc/sudoers.d/` | 唯一命中 `/etc/sudoers.d/90-openclaw:1` |
| `id` | desmond ∈ `sudo`,`docker` 组 |
| `command -v openclaw` / `npm ls -g` | 空(已卸载) |
| systemd unit/timer(系统+用户)、crontab、`/etc/cron.d` | 无 openclaw 条目 |
| `fd -H -i openclaw ~ --max-depth 3` / `pgrep -af openclaw` | 空 / 仅 pgrep 自身 |

结论:免密仅来自 90-openclaw;openclaw 本体在 2026-10-29 卸载时已清,唯此文件残留。

## 2. 变更执行

```bash
# ① sudoers 移出(放在第一步:opencode deny 生效后会话自身无法再 sudo)
sudo -n mv /etc/sudoers.d/90-openclaw /tmp/opencode/90-openclaw.removed
```

`~/.config/opencode/opencode.jsonc` 追加(MCP 段原样保留):

```jsonc
  "permissions": [
    { "action": "shell", "resource": "sudo *", "effect": "deny" }
  ],
  "policies": [
    { "action": "tool.use", "resource": "shell:sudo *", "effect": "deny" }
  ]
```

语法依据:opencode.ai/docs/permissions(V2:action `shell` + 末尾 ` *` 模式同时匹配裸命令;`policies` 为硬拒绝,项目级配置与保存的审批均不可覆盖;配置热加载无需重启)。

## 3. 验证

| 验证 | 结果 |
|---|---|
| `sudo -n -k true` | `sudo: a password is required` ✅ |
| 会话内 `sudo -n true` | opencode 权限层拦截:`{"type":"permission.rejected","message":"Permission denied: shell"}` ✅ |
| `jq empty opencode.jsonc` | JSON valid ✅ |
| `pgrep -af openclaw` | 无进程 ✅ |

## 4. 备注

- 会话执行顺序敏感:sudoers 移除必须先于 opencode 配置写入,否则会话自断 sudo。
- `~/.claude/CLAUDE.md` 原 openclaw 铁律/token 同步章节已随 2026-11-14 指令更新移除,无过时引用。

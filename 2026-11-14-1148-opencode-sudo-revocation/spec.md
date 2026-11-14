# 取消 opencode/AI 会话 sudo 权限(清除 openclaw 免密残留)

日期: 2026-11-14 · 状态: 已完成 · 实施记录: [implementation.md](implementation.md)
- 前置任务: [2026-10-29-1516-openclaw-uninstall](../2026-10-29-1516-openclaw-uninstall/)(openclaw 本体卸载——本次清除其遗漏的最后一件残留)

## 背景与决策

检查 AI 会话权限时发现 `desmond` 仍持有全量免密 sudo:

```
$ sudo -n -l
User desmond may run the following commands on brave-goose-1:
    (ALL : ALL) ALL
    (ALL : ALL) NOPASSWD: ALL
```

免密来源为 `/etc/sudoers.d/90-openclaw`(2026-09-03 创建,单行 `desmond ALL=(ALL:ALL) NOPASSWD: ALL`,当初 openclaw 安装)——**2026-10-29 openclaw 卸载时漏删的最后一件残留**。任何以 desmond 身份运行的进程(含 AI agent 会话、被投毒的依赖)都能借此无提示取得 root。

**用户决策(2026-11-14 确认)**:双保险——① 删除 sudoers 免密规则;② opencode 配置层 deny sudo 命令。openclaw 已停用,残留一律清除,不保留任何可重建免密的机制。

## 变更范围

1. sudoers:`/etc/sudoers.d/90-openclaw` 移出(备份 `/tmp/opencode/90-openclaw.removed`)
2. opencode 全局配置 `~/.config/opencode/opencode.jsonc`:
   - `permissions` + `{ "action": "shell", "resource": "sudo *", "effect": "deny" }`(含裸 `sudo`)
   - `policies` + `{ "action": "tool.use", "resource": "shell:sudo *", "effect": "deny" }`(硬拒绝,项目级配置无法覆盖)
3. openclaw 残留复查:二进制 / npm 全局包 / systemd 单元与 timer(系统+用户)/ crontab 与 /etc/cron.d / home 目录(含隐藏,深度 3)/ 运行中进程——全部为空,无任何可跑 doctor/update 或重建免密文件的东西

## 现在的权限状态

- **用户本人**:sudo 仍可用,需输密码(来自 `sudo` 组的 `(ALL:ALL) ALL`,基础 `/etc/sudoers` 授予)
- **opencode / AI 会话**:三层拦截——opencode 权限层 deny → 策略层硬拒绝 → OS 层 sudo 需密码(非交互会话无法提供)

## 回退

```bash
sudo mv /tmp/opencode/90-openclaw.removed /etc/sudoers.d/90-openclaw
```

注意:免密已失效,回退需在用户本人终端输密码执行;备份在 `/tmp`,重启即清空(内容仅一行,必要时手写恢复)。opencode 侧删除 jsonc 中的 `permissions`/`policies` 两段即可。

## 验收标准

- [x] `sudo -n -k true` 返回 `sudo: a password is required`(免密失效)
- [x] 本会话实测 `sudo -n true` 被 opencode 权限层拦截(`permission.rejected`),deny 即时生效
- [x] `jq empty` 校验 `opencode.jsonc` 语法完好,MCP 配置未动
- [x] openclaw 全量复查无残留(进程/包/服务/定时任务/文件)

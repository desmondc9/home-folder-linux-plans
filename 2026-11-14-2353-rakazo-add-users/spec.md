# Rakazo 自部署实例添加用户（方式调研 + 两个账号创建）

日期: 2026-11-14 · 状态: 已完成 · 实施记录: [implementation.md](implementation.md)
- 前置档案: [2026-11-12-1517-rakazo-deploy](../2026-11-12-1517-rakazo-deploy/)（初始部署）、[2026-11-14-1255-rakazo-reenable](../2026-11-14-1255-rakazo-reenable/)（重启用，当前 v0.11.0 全新实例）

- 环境: Bandwagon VPS signal-align（Ubuntu 26.04，即 `~/rakazo-deploy` 部署机）；Rakazo v0.11.0 官方 published images compose 栈（api/web/worker/supervisor/postgres/computer）；opencode 会话执行

## 背景与需求

实例自 2026-11-14 重启用以来只有 bootstrap 创建的单一账号（`desmond****@outlook.com`，与部署 README 一致）。需求：再添加两个用户——Carrie 与 Karina。

部署现状（决策依据）：`SIGNUPS_ENABLED=false`、`SIGNUP_ALLOWLIST=` 空、`AUTH_PASSWORD_ENABLED=true`、**未配置任何邮件服务**（`SMTP_URL`/`EMAIL_PROVIDER` 空）、无 OIDC、无 SCIM token。

## 调研结论（可复用知识）

权威来源：官方 v0.11.0 tag 下 `docs/self-host-accounts.md`。

| 方式 | 适用性 | 原因 |
|---|---|---|
| `bootstrap-owner` CLI（仓库封装为 `scripts/bootstrap-account.sh`） | ✅ 本例采用 | 专为无邮件部署设计；注册关闭时可用；创建**已验证**普通账号 + 个人 workspace；**可对每个新用户重复执行** |
| 临时开放注册（`SIGNUPS_ENABLED=true` 重启） | ⚠️ 不采用 | 无邮件服务时公开注册永不标记邮箱已验证；且 `env-overlay.sh` 每次升级会把该项刷回 `false` |
| `SIGNUP_ALLOWLIST` 白名单 | ❌ 不可行 | 官方明确：白名单注册要求邮箱验证 + 邮件投递，本实例无 SMTP |
| OIDC SSO / SCIM 目录供给 | 杀鸡用牛刀 | 适合整组织接 IdP；SCIM 建的账号无密码、未验证，仍需 SSO/邮件码登录 |
| 直插 Postgres | ❌ 禁止 | Better Auth 密码哈希等在应用层，非官方路径 |

关键行为细节（v0.11.0 文档明确）：CLI 遇已存在**未验证**同邮箱账号时，密码匹配则顺带验证；遇已存在**已验证**账号则不动（改密码需用户登录后在应用内操作，无需邮件服务）。Rakazo 无管理员角色，`RAKAZO_ADMIN_EMAILS` 仅管插件审核/stdio MCP/额度授予，与账号创建无关。

**勘误**：`~/rakazo-deploy` README 第 34 行"新账号需临时改 `.env` 重启"为过时说法——v0.11.0 起 bootstrap CLI 可重复用于后续账号，无需动 `.env`（待 PR 修正，见 implementation.md 跟进项）。

## 脱敏决策

本仓库为公开仓库，遵循 [CLAUDE.md](../CLAUDE.md) 红线：

1. **两个初始密码一律不入库**——仅经 opencode 会话一次性交付（生成方式 `openssl rand -base64` 截 20 位字母数字，满足脚本 ≥16 要求），用户登录后应自行改密。
2. **两位用户的邮箱部分掩码**（第三方 PII）：`kaiq****@icloud.com`（Carrie）、`kari****@outlook.com`（Karina）。真实值权威来源：rakazo postgres `user` 表（`docker exec rakazo-postgres-1 psql -U rakazo -d rakazo ...`）。
3. 基础设施信息（域名 `rakazo.signal-align.com`、服务结构、命令）按本仓库定位可入库；本次操作未涉及任何 token/key。

## 验收标准

- [x] 两个账号存在于 `user` 表且 `emailVerified = t`（见 implementation.md 验证段）
- [x] 初始密码未写入任何被 git 跟踪的文件
- [x] 提交前 gitleaks 扫描通过
- [x] README.md 任务索引补行

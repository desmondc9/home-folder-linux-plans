# 实施记录:Rakazo 添加两个用户

执行时间: 2026-11-14 20:32 CST（DB `createdAt` 12:32 UTC，容器时区 Etc/UTC）· 执行人: opencode 会话（desmond 确认）

## 步骤

| # | 操作 | 结果 |
|---|---|---|
| 1 | 调研：官方 v0.11.0 `docs/self-host-accounts.md` + 本机 `.env` 状态核对 + api 容器 `dist/cli/` 清点 | ✅ 结论见 spec.md 表格，选 bootstrap CLI |
| 2 | 生成 20 位随机密码（`openssl rand -base64 18 \| tr -d '/+=' \| cut -c1-20`），经环境变量传入 `RAKAZO_BOOTSTRAP_PASSWORD=... scripts/bootstrap-account.sh kaiq****@icloud.com` | ✅ 输出 `Account verified` |
| 3 | 同法为 `kari****@outlook.com` 执行 | ✅ 输出 `Account verified` |

密码全程只存在于环境变量与会话输出，未落盘、不入档（红线 1）；已当场交付 desmond 转交用户本人。

## 验证

DB 核验（`user` 表按 `createdAt` 排序，邮箱脱敏后）：

```text
desmond****@outlook.com | t | 2026-11-14 05:10 UTC   (原 bootstrap 账号)
kaiq****@icloud.com     | t | 2026-11-14 12:32 UTC   (Carrie)
kari****@outlook.com    | t | 2026-11-14 12:32 UTC   (Karina)
```

登录入口 `https://rakazo.signal-align.com`（移动端/桌面 App 填同一自定义服务器地址）。两账号均为已验证普通账号，各含独立 personal workspace；服务器未配模型，用户 onboarding 时自行连接模型 API key。

## 账号清单（脱敏）

| 用户 | 邮箱（掩码） | 初始密码 |
|---|---|---|
| Carrie | `kaiq****@icloud.com` | 不入库（会话一次性交付） |
| Karina | `kari****@outlook.com` | 不入库（会话一次性交付） |

## 运维备注

- 停用/恢复某账号（未设 `SCIM_BEARER_TOKEN` 时可操作任意账号）：
  `docker compose --env-file .env -f docker-compose.images.yml exec api node dist/cli/account-status.js deactivate <邮箱>`（或 `reactivate`）。停用即断会话/暂停 routines/拒新登录，保留其 bots/聊天/文件。
- 每次加人照旧 `scripts/bootstrap-account.sh` 一次即可，不动 `.env`、不重启。

## 跟进项（未做）

- [ ] `~/rakazo-deploy` README 第 34 行过时说法（"新账号需临时改 `.env` 重启"）应修正为"bootstrap CLI 可重复使用"，并把新账号记入该 README——按该仓库惯例走 plans/ → worktree → PR。

## 经验

- `bootstrap-owner` 不只是"首账号"工具：v0.11.0 文档明确支持遇已验证账号跳过、遇未验证账号密码匹配即验证，因此可安全重复执行，是最省事的加人路径。
- 无邮件部署的代价要记牢：白名单注册、邮件验证码登录、忘记密码恢复均不可用；已登录用户改密码不需要邮件。

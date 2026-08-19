# frp token 泄露清除与机密入库禁令

日期:2026-08-19 · 状态:git 侧已完成;**token 轮换用户决定暂不执行(旧值仍生效,风险见下)**

## 背景

[../2026-08-19-frp-config-archive/](../2026-08-19-frp-config-archive/) 归档 frp 双端配置时,把 `auth.token` 明文随 `frpc.toml`(commit `cdacf0a`)和 `frps.toml`(commit `2446ebf`)提交并推送。当时的认知是"本仓库为私人 plans 仓库,入库符合惯例"——**这是错的**:`desmondc9/home-folder-linux-plans` 在 GitHub 上是 **PUBLIC**。任何拿到 token 的人都能向 VPS 的 frps 注册代理(受 `allowPorts` 白名单限制,但仍可占用/冒用已放行端口)。

## 现状分析(发现时)

- 受影响 commit:`cdacf0a`、`0c14274`、`2446ebf`、`45c815e`、`11fd89c`、`f0d8ff3`(token 存在于这些快照的 `frpc.toml`/`frps.toml`,含历史路径 `2026-08-19-cloudflare-zerotrust-removal/frp/frpc.toml`)。
- 全历史排查:gitleaks v8.28.0 `gitleaks git` 全量扫描,除 frp token 外**无其他泄露**(无 tskey/hskey/私钥/密码/CF token);人工复核 32+ 位 hex 与 base64 key 模式,其余均为 commit SHA。
- 文档中 3 处"私人仓库"错误表述(zerotrust-removal design/implementation、frp-config-archive implementation)是事故的认知根源。

## 解决方案

1. **备份**:`git bundle create /tmp/plans-backup-before-secret-scrub.bundle --all`。
2. **清历史**:`git filter-repo --replace-text`,token → `__FRP_TOKEN_REDACTED__`,18 个 commit 全部重写。
3. **验证**:全历史 `git grep` 0 命中;gitleaks 复扫 `no leaks found`。
4. **强推**:`git push -f origin main`(`f0d8ff3...1963110 forced update`)。
5. **纠错**:修正文档中"私人仓库/入库符合惯例"的说法;frp-config-archive 快照注明"已脱敏"。
6. **立规**:新建 [../CLAUDE.md](../CLAUDE.md),写入机密禁令与泄露处置 SOP。
7. **轮换**(建议项,用户 2026-08-19 决定暂不执行):公开过的 token 应当作已死,生成新 token 同步改 VPS `frps.toml` + 本机 `frpc.toml`,两端重启。历史清除只止血,轮换才除根——GitHub 对已强推掉的 commit 仍有缓存期,且无法排除已被人 clone/抓取。**在轮换之前,旧 token 对任何看过公开历史的人仍然有效。**

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| GitHub 缓存旧 commit / 已被第三方抓取 | token 轮换,旧值作废 |
| 强推重写公开历史 | 个人档案库无协作者,影响可控 |
| 轮换时双端不一致导致 frp 断链 | 先改 frpc 再改 frps(frpc 自动重连);断链期间 tailnet/SSH 直连 VPS 不受影响 |

## 验收标准

- [x] gitleaks 全历史扫描无 leak
- [x] GitHub 远端历史已不含 token(强推完成)
- [-] ~~新 token 双端生效~~ 用户决定暂不轮换,接受旧 token 残留风险(见上)

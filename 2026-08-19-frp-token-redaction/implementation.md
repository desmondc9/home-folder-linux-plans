# frp token 泄露清除与机密入库禁令 — 实施记录

对应说明:[design.md](design.md) · 日期:2026-08-19

## 任务清单

- [x] 定位泄露:`frpc.toml`/`frps.toml` 的 `auth.token` 明文入库并推送到 **PUBLIC** 仓库
- [x] 全历史排查:gitleaks v8.28.0 `gitleaks git` 扫描 18 个 commit —— 仅 frp token 一处机密,无其他泄露
- [x] 备份:`git bundle create /tmp/plans-backup-before-secret-scrub.bundle --all`
- [x] 清历史:`git filter-repo --replace-text`(token → `__FRP_TOKEN_REDACTED__`),全部 commit 重写
- [x] 验证:全历史 `git grep` 0 命中;gitleaks 复扫 `no leaks found`
- [x] 强推覆盖远端:`git push -f origin main`(`f0d8ff3...1963110 forced update`)
- [x] 修正 3 处"私人仓库"错误表述(zerotrust-removal design.md/implementation.md、frp-config-archive implementation.md),frp-config-archive design.md 快照表注明"已脱敏"
- [x] 新建 [../CLAUDE.md](../CLAUDE.md):机密禁令 + 提交前 gitleaks 扫描 + 泄露处置 SOP
- [ ] 轮换 frp token:新 token → 本机 `/etc/frp/frpc.toml` + VPS `/etc/frp/frps.toml` → 两端 restart → 验证链路

## 变更文件表

| 文件 | 变更 |
|---|---|
| `2026-08-19-frp-config-archive/frpc.toml` / `frps.toml` | token → `__FRP_TOKEN_REDACTED__`(全历史) |
| `2026-08-19-frp-config-archive/design.md` / `implementation.md` | 快照表注明脱敏;纠正"私人仓库"说法 |
| `2026-08-19-cloudflare-zerotrust-removal/design.md` / `implementation.md` | 纠正"私人仓库"说法,补脱敏要求 |
| `CLAUDE.md`(新建) | 机密红线规则 |
| `2026-08-19-frp-token-redaction/`(新建) | 本档案 |

## 备注

- 备份 bundle 在 `/tmp/plans-backup-before-secret-scrub.bundle`(重启即失;其中仍含旧 token,轮换后无留存价值,重启自然清除)。
- GitHub 对已强推 commit 的缓存清除不做保证(需联系 support 才彻底),**所以不能靠清历史代替轮换**。
- 教训:归档含凭据的配置时,"先脱敏再入库"是唯一步骤顺序;"仓库是私人的"这种前提必须先用 `gh repo view --json visibility` 验证,不能凭印象。

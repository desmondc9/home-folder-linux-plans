# Decommission the LibreChat stack; adopt Kimi Chat

> 待合入路径：`librechat-deployment/docs/adr/0010-decommission-librechat-adopt-kimi.md`（本文件为草稿，定稿时删除此引言）

**Status**: accepted（2026-09-22）

**Context**: LibreChat（VPS compose + ACA warm standby，含 codeapi/redis/rustfs 附属栈）作为自托管聊天前端，搜索能力与 OpenClaw 连接性均不及 Kimi Chat（官方 Web，经标准 openclaw channel/npm plugin 接 OpenClaw），却持续占用 Bandwagon VPS 约 1.2G+ RAM 与 Azure 常驻费用。

**Decision**: 全栈下线——VPS 四个 compose 项目 `down --rmi all`（配置目录与密钥文件保留）、Azure `signal-align-librechat` RG 整删、librechat/codeapi 域名与 nginx vhost/证书/ufw 规则移除、OpenClaw chatCompletions 端点关闭（恢复 ADR-0002 红线）、四 repo archive。聊天记录保留于 MongoDB Atlas M0（免费层，VPS 每日 mongodump 至 `~/atlas-backups/`）。

**Consequences**:

- **auth 栈明确不在下线范围**：`signal-align-auth`（VPS compose + Azure RG 全部，含 `signal-align-kv` 与 5 个 ACA standby）是 reading-app / books-and-articles 的活体 IdP（OIDC + JWKS + S2S token），原样保留；其 ACA standby 为 DR 保险有意保留，非遗漏。
- OpenClaw gateway、Atlas M0、每日备份 cron、derp/headscale/tailnet 不受影响。
- 恢复路径：clone 本 repo（archive 可解档）→ 按 runbook `compose up -d` + CD 重建 ACA；数据在 Atlas。
- 本 ADR **supersedes** ADR-0002（chatCompletions 暴露边界——端点已关闭）与 ADR-0005（ACA warm standby 双目标——standby RG 已删除）中与 LibreChat 直接相关的部分。

**Considered Options**: scale-to-0 保留 ACA（否决：无主站即无 standby 意义，且有日志/环境残留费用）；导出聊天记录后删 Atlas（否决：M0 免费保留即可，已有每日备份）。

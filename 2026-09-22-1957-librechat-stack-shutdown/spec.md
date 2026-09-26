# LibreChat 全栈下线（保留 auth IdP）— 设计规格

- 日期：2026-09-22 19:57 CST
- 环境：Bandwagon VPS `brave-goose-1`（104.194.83.82，Ubuntu 24.04，4C/3.9G）+ Azure 个人订阅 `2dba9ddf`（azg / `AZURE_CONFIG_DIR=~/.azure-global`）
- 性质：个人环境运维下线任务（bounded）；无 Kanban 工作项（sdk2api 先例）
- 状态：**共识已达成（grilling 三轮 + 实证核验），待用户批准 spec 后执行**

## 1. 背景与决策

用户日常聊天前端从 LibreChat（librechat.signal-align.com，自托管 4 compose 栈 + ACA warm standby）切换为 **Kimi Chat**（官方 Web）。理由：Kimi 的搜索功能与 OpenClaw 连接性（标准 openclaw channel，npm plugin）均优于 LibreChat。停掉 Bandwagon VPS 上 LibreChat 专属的 CPU/Mem 占用与 Azure 计费。

三个 SSO 账号均为用户本人，无需通知期，立即执行。

## 2. 已实证的依赖地图（2026-09-22 探勘）

### 必须保留（reading-app / books-and-articles / OpenClaw 的活体依赖）

| 资源 | 证据 |
|---|---|
| `signal-align-auth` VPS compose（kratos/hydra/bridge，loopback 4433/4444/3000） | reading/books ACA env：`OAUTH_ISSUER=https://auth.signal-align.com/`、`OAUTH_JWKS_URL`、books `S2S_TOKEN_URL=/oauth2/token` |
| nginx `auth` vhost + auth/identity/login 三域名（灰云 → VPS）+ LE 证书 `signal-align-auth`（DNS-01 续期） | `getent` 实测三域名 → 104.194.83.82 |
| auth 数据库：Supabase（kratos_app / hydra_app schema） | `docker inspect` DSN 实证；与停机清单零交集 |
| Azure `signal-align-auth` RG **整体**：`signal-align-kv`（含 reading-app-dsn / reading-app-llm-api-key / books-app-dsn / books-app-s2s-secret）+ 5 个 auth ACA standby（hydra-public/admin、kratos-public/admin、bridge-app）+ env + 日志 workspace + 3 个 managed identity | KeyVault 引用来自 ca-reading-api / ca-books-api 配置实证；standby 为用户决策保留（DR 保险），活路径对 ACA FQDN 引用为 0 |
| OpenClaw gateway（systemd user）+ openclaw-tailnet vhost；derp/headscale/tailnet | openclaw.json 对 redis/rustfs/codeapi 零引用 |
| MongoDB Atlas M0（LibreChat + codeapi 库） | 用户决策保留为冷归档；`/etc/cron.d/librechat-atlas-backup` 每日 04:15 备份到 `~/atlas-backups/`（实测新鲜，7.4M/天；`cron-error.log` 为 mongodump stderr 进度，非错误） |

### 下线（纯 LibreChat 专属，无外部消费者）

| 资源 | 说明 |
|---|---|
| VPS compose：`librechat-deploy`（api/client + chat-meilisearch + 已退出的 chat-mongodb）、`codeapi-deploy`（6 容器）、`redis-deploy`、`rustfs-deploy` | shared-infra 网络成员仅 codeapi 系；reading/books 生产用 Azure Blob + Supabase/自建 PG；rustfs 仅 books 本地开发用（开发机，非 VPS） |
| Azure RG `signal-align-librechat` 整删（librechat app/env、`salignlibrechat` 存储、`librechat-aca-logs`、`salign-librechat-kv`、托管证书） | 无外部引用（reading/books 的 secret 全在 `signal-align-kv`） |
| nginx `librechat`/`codeapi` vhost；DNS `librechat.`/`codeapi.`（A+AAAA）；对应 LE 证书（certbot delete）；ufw 172.28.0.0/24→18789 规则 | 随停服当天清理 |
| OpenClaw `gateway.http.endpoints.chatCompletions.enabled` → false | Kimi 走 npm plugin channel，18789 无消费者；恢复 ADR-0002 的暴露面红线 |
| GitHub：librechat / codeapi / redis / rustfs-deployment 四 repo | ADR/退役横幅合入后 archive |

## 3. 关键决策与理由（用户逐项确认）

1. **一步到位**：`docker compose down --rmi all`（保留卷，共 5.6M 无关紧要；保留 `~/librechat-deploy` 等配置目录与 `~/librechat-keys.env`）。恢复 = repo + runbook + `compose up -d`。
2. **聊天记录不导出**：Atlas M0 免费保留 + VPS 每日备份已实证存在。接受"平台政策变更"为已知残余风险。
3. **Azure 直接删 RG**（不 scale-to-0）；standby 无主站即无意义，且 scale-to-0 仍有日志/环境残留费。
4. **auth ACA standby 5 app 保留**（用户最终决策）：auth 现为 reading/books 唯一 IdP，热备价值 > 费用。
5. **chatCompletions 关闭** + ufw 规则删除，恢复 ADR-0002 红线；重启 `openclaw-gateway` 的秒级断连窗口选低峰。
6. **停服当天即删 vhost + DNS**（避免访客撞证书错误页）；LE 证书用 `certbot delete` 清除避免续期失败噪音。
7. **四 repo archive**（searxng-deployment 先例），退役 PR 中同时禁用 aca-cd/vps-cd/foundry-sync/cd 等部署 workflow。

## 4. 风险与缓解

| 风险 | 缓解 |
|---|---|
| openclaw-gateway 重启闪断 | 秒级窗口，选低峰；重启后验证 kimi channel |
| RG 删除不可逆 | 恢复路径 = librechat-deployment repo CD（ADR-0004/0005 体系）；用户已确认 |
| Bandwagon 快照窗口 | 可选前置：执行前在 BWH 面板确认近 7 天快照存在 |
| 停错栈（auth 误伤） | runbook 每步带验证；`docker compose down` 仅在四个专属目录内执行 |

## 5. 验收标准

- [x] VPS `docker compose ls` 仅剩 `signal-align-auth`；`docker ps` 仅 auth 三容器（2026-09-22 实测）
- [x] `https://auth.signal-align.com/.well-known/jwks.json` 200；reading/books API 0.5s 响应（JWKS/OIDC 链路无损）
- [x] OpenClaw gateway active + kimi-bridge 重连成功；18789 的 172.28.0.0/24 规则已删；chatCompletions/models 均 404
- [x] `librechat.`/`codeapi.` 域名无应答记录（CF API remaining=0 + dns.google 复核）；auth/identity/login 正常解析
- [x] Azure：`signal-align-librechat` RG 已删除（~13 分钟完成，2026-09-22 确认）；`signal-align-auth` RG 完整（14 项资源，5 standby 在线）
- [ ] 次日 `~/atlas-backups/2026-09-23.archive` 正常生成（**尾项：次日自查**；备份 cron 与下线无交集，预期正常）
- [x] 四 repo 已 archive（PR #134/#28/#3/#2 squash merge），含 ADR-0010 与退役横幅；新增内容无真实密钥
- [x] VPS `free -m` / `df -h` 释放量已记录进 implementation.md（RAM used -198M、available +198M；盘 82%→71%，净 ~8G）

## 6. 性能与容量（Step G verify gate）

**不触发**：纯服务下线，无 SQL/查询/批写/缓存/外呼代码路径变更。实际回收（2026-09-22 实测）：VPS RAM used 1696→1498M（空闲容器 RSS 本小于估算值）、磁盘 60G→52G（82%→71%，含 prune 2.9G）；Azure 消除 librechat RG 全部费用（删除进行中）。保留项（auth ACA standby 5 app 常驻）为用户明确接受的费用。

## 7. 引用

- 前序：`~/plans/2026-09-07-1141-librechat-openclaw/`、`~/plans/2026-09-07-1329-librechat-websearch/`
- 先例：`~/plans/2026-09-01-1537-cursor-sdk2api-shutdown/`
- Repos：desmondc9/{librechat,codeapi,redis,rustfs}-deployment（docs/adr/ 已有 0001–0009）
- 本目录：`implementation.md`（分阶段 runbook）、`adr-0010-decommission-librechat.md`（待合入 librechat-deployment）

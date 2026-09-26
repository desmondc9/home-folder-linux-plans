# LibreChat 全栈下线 — 实施 runbook

对应 spec：本目录 `spec.md`（共识 2026-09-22）。前置：本文件任务全部 `- [ ]`，执行时逐项勾选并记录输出摘要。

**执行记录：2026-09-22 20:00–21:2x CST，全部完成**（除两项尾项见下）。

## Phase 0 — 前置确认（只读）

- [x] BWH 面板确认近 7 天快照存在（可选）→ 跳过（可逆操作 + 数据在云端）
- [x] 基线：13 容器 / RAM used 1696M、available 2282M / 盘 60G(82%) / JWKS 200
- [x] ACA 基线：8 app（librechat + 5 auth + reading/books）

## Phase 1 — VPS 停栈（保留 auth）

- [x] `librechat-deploy` / `codeapi-deploy` / `redis-deploy` / `rustfs-deploy` 依次 `down --rmi all`，网络一并移除
- [x] `docker system prune -f`：回收 2.947GB
- [x] 验证：`docker compose ls` 仅 `signal-align-auth running(3)`；`docker ps` 仅 auth 三容器
- [x] 保留物：四个配置目录 + `~/librechat-keys.env` + `~/atlas-backups` + docker 卷（未用 -v）
- 实测释放：**RAM used 1696→1498M**（available 2282→2480M；低于 spec 估算——空闲容器 RSS 本就小）；**盘 60G→52G，82%→71%（净 ~8G）**

## Phase 2 — Azure 删 RG（signal-align-librechat）

- [x] `az group delete --yes --no-wait` 发起；状态已进入 `Deleting`，收尾轮询挂后台（含 KV/ACA env 的 RG 需 10–20 分钟）
- [x] **未动** `signal-align-auth` RG：14 项资源完好，5 个 standby app 全部在线
- [x] `az containerapp list`：无 librechat 相关

## Phase 3 — VPS 边缘清理 + OpenClaw 收口

- [x] 删 `sites-enabled/{librechat,codeapi}`（及 sites-available）；`nginx -t` 通过、reload OK（`headscale-new` 为在途他项工作，未触碰）
- [x] certbot delete：`librechat.signal-align.com`、`codeapi.signal-align.com` 两证书已删；保留 bandwagon/derp/headscale/signal-align-auth
- [x] ufw 删 172.28.0.0/24→18789 规则；tailscale0 两条规则保留
- [x] OpenClaw：备份 `openclaw.json.bak-20260922` → `chatCompletions.enabled=false` → restart → `active`；**kimi-bridge plugin v0.27.1 重连成功**（`[im] subscribe connected` → kimi.com/api-ws）；实测 `/v1/chat/completions` 与 `/v1/models` 均 **404**（整个 OpenAI 兼容 HTTP 面随端点关闭，比预期更紧）
- [x] DNS：删 librechat A+AAAA（2 条）+ codeapi A（1 条）；login/auth 记录保留；dns.google 验证 librechat 无应答、auth 双记录
- [x] reading/books 验证：JWKS 200；两 API 均 404@0.5s（`/` 无路由属正常；初测 000 为 ACA 冷启动超时，复测即通）

## Phase 4 — repo 退役（四 repo，PR → merge → archive）

- [x] **librechat-deployment PR #134**（squash）：ADR-0010 + 0002/0005 加 superseded 注 + README 横幅 + `aca-cd/vps-cd/foundry-sync` → `.disabled`
- [x] **codeapi-deployment PR #28**（squash）：横幅 + `cd.yml.disabled`
- [x] **redis-deployment PR #3**、**rustfs-deployment PR #2**（squash）：横幅
- [x] 四 repo 均 `archived=true`（`gh api -X PATCH repos/… -f archived=true`；本机 gh 版本无 `--archived` 旗标）
- [x] 新增内容无任何真实密钥（横幅/ADR 仅含路径与资源名）

## Phase 5 — 收尾验证

- [x] spec §5 清单除下列两项外全绿
- [x] **尾项 1**：`signal-align-librechat` RG 删除完成 ✅（发起后 ~13 分钟，2026-09-22 21:5x CST 确认 GONE；终态 VPS：RAM used 1390M / available 2588M，盘 52G 71%）
- [ ] **尾项 2**：次日验证 `~/atlas-backups/2026-09-23.archive` 生成（04:15 CST，用户或次日会话自查；备份 cron 与本下线无交集，预期正常）

## 变更清单（文件/资源 → 动作）

| 对象 | 动作 |
|---|---|
| VPS 4 compose 项目 | down --rmi all，目录保留 ✅ |
| Azure RG signal-align-librechat | 整删（Deleting→完成）✅ |
| nginx vhost ×2、LE 证书 ×2、ufw 规则 ×1、DNS ×3 条 | 删除 ✅ |
| openclaw.json chatCompletions | enabled=false（备份先行）✅ |
| GitHub ×4 repo | PR（ADR/横幅/禁用 workflow）→ squash merge → archive ✅ |
| 其余一切（auth 全家、OpenClaw、Atlas、备份、reading/books） | 未动，已验证无损 ✅ |


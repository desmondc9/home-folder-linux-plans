# implementation — Rakazo 部署（机器档案）

对应 spec: [spec.md](./spec.md) · 权威细节: 私有仓库 desmondc9/rakazo-deploy（Issue #1、PR #2/#3、plans/2026-11-12-1517-rakazo-initial-deploy/）

## 执行时间线（2026-11-12）

1. 预检：Docker 29.1.3 满足官方要求（podman 4.9 API 不足弃用）；3100/5173 空闲；nginx stream SNI 默认路由 14443 无需改；ghcr 可达；最新稳定 release = v0.10.0（前一日发布）
2. 建私有仓库 rakazo-deploy + Issue #1 + worktree（feature/rakazo-initial-deploy）
3. 官方 v0.10.0 四件套固定入仓（compose/env example/installer/egress 脚本）+ RAKAZO_VERSION pin + 6 个幂等脚本 + nginx vhost + ci/daily-upgrade workflows + README/AGENTS/CONTEXT
4. 本地验证：shellcheck 全绿、dummy-secrets compose config 通过、env-overlay 双跑幂等、workflow YAML/触发器解析
5. PR #2 → CI 绿 → squash 合并
6. Cloudflare 加 A/AAAA（DNS-only）；本机 `deploy.sh`：installer 生成 .env（6 独立随机 secret）→ overlay（v0.10.0 pin、三源 HTTPS、SIGNUPS_ENABLED=false、egress 预设）→ host-setup（egress 规则+systemd、两段式 vhost+certbot 取证）→ pull+up --wait 全 healthy
7. bootstrap-owner 建号（Account verified）；deploy key + repo secret + `gh auth setup-git`
8. 发现并修复 workflow 边界 bug（force 重部署同 tag 时空 pin commit 失败→误入回滚）：PR #3 合并
9. `workflow_dispatch(force=true)` 全链路验证：run 43175586443 success（pin 跳过空提交→SSH deploy→health→external 200，回滚未触发）
10. 验收证据回填 repo plans/；Issue #1 评论验收表；worktree 清理；本档案归档

## 验收（全过）

| 项 | 结果 |
|---|---|
| 内部 health | ok:true, sandbox:"docker" |
| 外部 | https://rakazo.signal-align.com 200；LE 证书 CN 匹配，2027-02-10 |
| 服务 | postgres/supervisor/api/worker/web 全 Up(healthy) @ app:v0.10.0 |
| 注册/账号 | SIGNUPS_ENABLED=false；desmondc9@outlook.com 已验证（密码未落盘，会话交付） |
| 流水线 | force run success；cron 0 20 * * * 即北京 04:00 |

## 遗留/后续

- [ ] 模型未配置（按用户决策，UI onboarding 自连）——连接前 bot 无法回复
- [ ] 首次备份尚未执行（.env + pgdump 到 ~/atlas-backups，建议本周内）
- [ ] 首个真实升级窗口待观察（下一个官方 stable release 发布后的 04:00 run）

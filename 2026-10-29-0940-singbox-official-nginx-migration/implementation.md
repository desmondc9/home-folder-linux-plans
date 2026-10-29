# 实施记录

状态：按用户纠正，仅修改本机必要配置；不再开发/发布框架，不再推送运维记录。#68 已通过 #69 撤销（main=2ba67fd，与#68前44a084d内容一致）。以下本机记录只提交本地Git。

## 当前本机操作

- [x] 正式备份：`/var/backups/sing-box-migration/2026-10-29-111755-local/original.tar.gz`（root目录0700、文件0600，含旧core/脚本/配置/service、Nginx、auth链接目标、LE证书和DNS凭据、续期调度、UFW规则）。
- [x] SHA256：`b0b2d9d2a32535020a38971a27bba01365a107ebac3f9c72f2167fdeb2a0a6a3`；已试解包并验证关键内容、owner/mode、symlink。原始备份不入Git，至少保留30天。
- [x] 官方1.14.4安装到 `/usr/local/lib/sing-box/1.14.4/`，校验官方archive摘要；新建非登录sing-box用户，生成全新UUID/X25519/short ID，不入Git、不在聊天中打印。
- [x] 回环预览：新core24443 + 临时Nginx15443，两层stream后IPv4/IPv6 REALITY代理均HTTP200。原11域状态/跳转/CA/证书一致，7个health均200，所有非listen/real_ip指令保持。
- [x] bandwagon/derp/headscale三张证书通过官方Certbot5.8 reconfigure的真实DNS-01 staging验证（39.3/38.8/39.6秒），改为dns-cloudflare+null installer；活跃证书文件与derper PID未变。
- [x] 原7个renewal profile均DNS、无nginx installer；保留原03:00 DNS cron并增加reload前nginx -t，停用不支持DNS插件的旧系统timer。旧系统cron带systemd guard，不运行。
- [x] Cloudflare只读核实：vs灰云CNAME→bandwagon，后者灰云A/AAAA正确，无需DNS写入。
- [ ] 本机Nginx stream配置、既有站点/续期兼容验证后切换；不改项目源码或CD。
- [ ] 验证新443代理及原11域/health/证书；移除旧脚本和旧端口规则；私有客户端文件交付。

auth 的sites-enabled链接会指向 `/etc/nginx/sites-available/auth-local-edge` 的本机副本，不直接编辑 `~/signal-align-auth/nginx-auth.conf`。未来auth路由调整需人工同步本机副本；其他vhost仅改TLS监听/real_ip，保留路由。旧服务最终切换前仍运行，未触发生产重启。

私有客户端文件（0600、目录0700）：`~/.config/sing-box-client/vs.signal-align.com/2026-10-29-111755-local/client.json` 与 `client-uri.txt`。正式443切换前该连接尚未启用；临时预览单元会在切换/收尾停止，不安装永久测试框架。

## 历史记录（下述三阶段仓库方案已停止，不再执行）

- [x] 读取 `~/plans/CLAUDE.md`：此档案库直接 main commit/push，无 worktree/issue/PR；公开仓库禁止秘密入库。
- [x] 检查现有 Git 状态并 fetch；保留原有未跟踪的其他任务目录，不纳入本次提交。
- [x] 只读检查系统、sing-box 版本及脱敏入站摘要、Nginx 监听拓扑、UFW、DNS 与官方 release。
- [x] 记录初步需求、证据及不能确定的根因；没有导出或提交现有认证值。
- [x] 用户选择 A（vs 作连接域名，外部站点作 REALITY SNI）。
- [x] Cloudflare API 只读确认 vs 已是灰云 CNAME；无需修改 DNS。
- [x] 读取证书续期/调度、auth 源码与发布入口，fetch 对齐最新 origin/main（保留旧 checkout）。
- [x] 获取 Web 双栈状态/证书、目标 TLS、容量和可用日志基线；凭据未输出。
- [x] 编写完整设计：PROXY 分流中继、源码/CD 发布、KV 来源、受控切换和自动恢复。
- [x] 独立 builder-check 审阅：明确旧节点在切换时失效（不并行保留）、2 分钟包含恢复预算、续期预检在窗口前、外部用户验收在窗口后；已修订 spec，待用户批准。
- [x] 用户了解 host-only CD 扩展范围后回复「好的, 继续」，进入实施规划；实际维护时机/并发作业仍需切换前确认。
- [x] 创建 [umbrella#67](https://github.com/desmondc9/signal-align-umbrella/issues/67)，包含原始目标和可验证验收标准。
- [x] 编写三阶段计划并自审覆盖范围/接口/测试/故障情形；阶段 1/2 仅合并惰性工具，不发布生产。
- [x] 用户确认 Native；本人在隔离 worktree 实施，阶段末独立审阅。
- [x] 阶段 1 Task 1：配置/凭据 API，7 测试 RED→GREEN；官方核心校验配置成功。
- [x] 阶段 1 Task 2：严格 release selector，6 测试 RED→GREEN。
- [x] 阶段 1 Task 3：Nginx 候选与容器内18项真实协议验证；既有9项脚本测试不回归。
- [x] 阶段 1 全分支独立审阅：后端身份/路径与证书lineage盲点补强；三类错误候选变异均被捕获。
- [x] 阶段 1 [PR #68](https://github.com/desmondc9/signal-align-umbrella/pull/68)，最终提交6f13183；CI的changes/scripts通过，其他未涉及job按条件跳过。
- [ ] 阶段 1 合并（等待用户确认）；其后进入阶段 2。
- [ ] 确认生产配置源码/发布入口，落实备份、回滚与安全部署。
- [ ] 按获批计划实施、验证客户端及既有应用、检查 DNS-only。
- [ ] 归档脱敏结果和最终验收证据。

## 文档与 Git

只提交本任务文档和 README 索引。真实备份及未来客户端配置存仓库外，不能随文档跟踪。本机无 `~/Notebook`，没有可同步的本地域笔记。

## 分阶段实施入口

1. [协议与候选配置](./implementation-phase-1.md)：配置、严格 selector、Nginx PROXY/REALITY 协议契约，生产不变。
2. [备份与限时恢复](./implementation-phase-2.md)：备份/漂移、续期预检、systemd watchdog 的故障注入，生产不变。
3. [Release/CD 与生产迁移](./implementation-phase-3.md)：仅host发布入口、auth后续兼容、PR/CI/合并后受控部署与外部验收。

实施仓库遵循本身的 plans 文件名约定（implementation_plan_phase_01.md 等）；本目录保留公开脱敏的总体主档。阶段1/2可各自独立合并惰性工具，只有阶段3在获准维护时机触发生产发布，避免实现尚未齐全就改在线auth listener。

阶段1运行证据见 [phase-1-results.md](./phase-1-results.md)。此处「验证通过」仅指隔离候选环境，不代表本机生产已迁移。

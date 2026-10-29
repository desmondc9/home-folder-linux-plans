# 实施记录

状态：用户已选择 Native；阶段 1 配置与离线协议验证已实现，独立审阅发现的两项测试盲点已按RED→GREEN修复；尚未执行生产配置变更。

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

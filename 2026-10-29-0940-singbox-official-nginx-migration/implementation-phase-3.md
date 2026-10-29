# VPS-edge Release/CD 与生产迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 接入 host-only 发布入口，经 CI/PR 后备份并迁移本机，交付私有客户端配置与脱敏结果。
**Architecture:** 通用 CD 只负责严格分流，vps-edge reusable workflow读取同 tag 的配置和 westus2 KV，执行 phase 2 的事务 CLI。普通 auth 部署与该入口共用锁与已迁移布局，避免后续回写公网 HTTP 443。
**Tech Stack:** GitHub Actions、Azure OIDC/Key Vault、OpenTofu 1.12.5、SSH、前两阶段的 Python/Bash/Podman 契约测试。
**Spec:** [spec.md](./spec.md)，依赖 [phase 1](./implementation-phase-1.md) / [phase 2](./implementation-phase-2.md) 已合并；[umbrella#67](https://github.com/desmondc9/signal-align-umbrella/issues/67)。

## Global Constraints

- 生产仅合并 PR 后 `gh release create vYYYY.MM.DD[-N]` → Actions CD；release notes 单独一行 `deployment-target: vps-edge`。
- host-only 不运行任何 app build/compose/database migrate；不得升级/重启 OpenClaw，不改 LibreChat 文件。
- Vault `signal-align-kv-w2`，一个 `sing-box-vs-credentials` JSON secret；掩码所有 credential fields，真实文件不得 artifact/cache或回显。现有 vs DNS-only 不改。
- 2 分钟维护/恢复总预算；进入 T0 前向用户确认实际切换时机、没有并发 Nginx 作业。未确认不创建激活 release。
- ≤3 points/一天，分支 `feature/singbox-vps-edge-release`，独立 worktree；每阶段 full local unit/contract绿后才 push/PR。

## Review Focus

1. edge发布误触发 auth/DB 或旧 Vault 故障路径；Task 1 workflow graph与 selector 双向测试。
2. 正常 auth 发版覆盖回 443，或 host迁移前已部署回环配置；Task 2 live marker/drift guard测试。
3. 默认 checkout不是 release tag、回滚凭据版本漂移；Task 1 pinned tag/secret version测试。
4. KV secret不完整或权限不足，不能生成替代值继续；Task 1 fail-closed/atomic bundle测试。
5. 本机 curl通过不代表用户公网网络可用；Task 3 分别记录 loopback/public/外部/IPv6/user-network验收。

## Files / boundaries

| 路径 | 职责 |
|---|---|
| `.github/workflows/{cd,ci,vps-deploy}.yml` | target分流/CI覆盖/正常auth部署的显式tag与共享锁 |
| `.github/workflows/vps-edge-deploy.yml` | host-only check/deploy/rollback，production OIDC，唯一现场操作入口 |
| `scripts/{deploy-vps,deploy-vps-edge,kv-render-edge}.sh` | auth兼容、edge staging/orchestration、独立秘密渲染 |
| `scripts/vps_edge/{credentials,workflow_contract}.py` | KV bundle schema与workflow静态契约辅助 |
| `infra/{keyvault,outputs}.tf` | 新 secret名称清单和不含值的 `vps_edge_deployment` 元数据输出 |
| `local/vps/nginx-auth.conf` | 替换成已验证的内部 TLS listen版本，由正常auth CD持续维护 |
| `scripts/tests/vps_edge/test_{release_workflow,credentials,deploy_guard}.py` | 以上发布行为测试 |
| `README.md`、`docs/runbook-vps-edge.md`、repo `plans/...` | 英文README、中文runbook/计划/性能门禁；不改AGENTS/CLAUDE除非确有新约定 |

## Interfaces

reuse `release_target`、`EdgeCredentials` 和 `vps-edge-host.sh`，不新增另一套协议配置。`vps_edge_deployment` 输出对象只含 phase 1 manifest的字段及schema，**不读取secret value进Tofu state**、不创建ACA资源/新权限。`kv-render-edge.sh OUTPUT_DIR [SECRET_VERSION]` 拒绝stdout交付真实值，OUTPUT_DIR必须0700，输出server.json/client.json/client-uri.txt均0600；只有明确的不存在才首次生成并写KV，403/429/网络错误均失败，不当作secret缺失。

GitHub dispatch保留既有 `tag`，新增 `edge_action: check|deploy|rollback`（默认check，release事件固定deploy）；dispatch根据指定tag对应的release notes（可为draft）解析target，不猜当前main或latest。只对解析为edge的release生效。rollback消费现有journal的 backup_dir/credential_version/previous_release_sha，不随机生成新凭据，不从不具备恢复工具的旧tag运行未知脚本。调用方固定checkout指定tag；JSON/脚本参数均经env/file传入，不把event文本直接插入shell源码。

共享互斥：workflow deployment concurrency `signal-align-bandwagon-deploy`，cancel-in-progress=false；主机真实排他以phase 2 host lock为准，避免绕开workflows的timer抢占。普通auth deploy在任何scp覆盖前持锁并检查`/var/lib/vps-edge/current.json`：存在且schema/sha有效方可用新内部auth布局；不存在则拒绝覆盖（此短过渡期不破坏现有运行服务）。edge首次激活后生成marker，所有后续auth部署验证stage后原子写入、nginx -t/reload，失败恢复旧文件。不再靠“symlink已存在就跳过reload”。

### Task 1: 只执行host的可重放Release workflow

- [ ] 写 `test_release_workflow.py`：edge不会到达build-push/migrate/普通deploy-vps；full仍走原图；未知selector整个图失败；tag/sha、production environment、concurrency、check默认不activate；workflow body传入env/file而不是shell插值。
- [ ] 写 `test_credentials.py`：bundle schema正确、首次生成只有一次原子secret set、重复读取用同版本、缺字段/不配对/403/429/网络失败均拒绝、stdout/log/artifact没有秘密；fake az命令只返回运行时测试凭据。
- [ ] 运行两组test确认红；实现新reusable workflow及KV renderer，首次bundle生成调用已校验官方核心，public/private pair一起存一个版本。生成/读取都不在chat中打印，不覆盖已有secret；新metadata只引用manifest和KV名称。
- [ ] host check运行read-only Tofu plan，保持现有image_tags，非本次允许变化（仅新增metadata output，无资源写变更）即失败；不输出旧static secrets。apply使用同一保存的plan并由用户可读核验；provider报未知漂移不能用-target掩盖。check仅staging/配置检查；deploy才允许调用prepare/activate；rollback只调用已存在的受审计restore。
- [ ] 安装/启用actionlint（如果缺少，官方release固定版本并校验），执行 `actionlint`、`tofu fmt -check`、`tofu init -backend=false && tofu validate`（在隔离worktree infra，避免污染其他工作）；重跑unit绿，commit `feat(vps-edge): add isolated release deployment scope`。

### Task 2: 后续auth发布安全与交付准备

- [ ] 写 `test_deploy_guard.py`：无live marker时普通auth部署不能scp覆盖；marker有效才使用新回环listen；漂移/语法错恢复旧文件且不重启应用；与edge/续期争锁时不能并发写；重复已应用版本幂等。
- [ ] 确认红，修正deploy-vps及其workflow固定tag/锁/验证逻辑；将phase1 auth候选放到正式源码路径。`deploy-vps-edge.sh STAGING_HOST RELEASE_SHA ACTION` 通过SSH调用phase2 CLI，stage目录0700，传输配置0600。参数只允许check/deploy/rollback，禁止拿网络输入当命令。
- [ ] 增加生产前baseline采集与比较：11域证书fingerprint/root状态+7专门health、80重定向、18790证书/握手原行为、WebSocket/DERP握手、未知/无SNI、双栈监听；已读的404/307不变。所有现场记录保存在root受限journal旁，公开summary脱敏。
- [ ] unit/全部模块contract绿，跑既有 `bash scripts/test-merge-image-tag.sh`、所有scripts bash -n；检查相关脚本shellcheck。采用本阶段改动的完整模块suite，不为本次无需执行的app业务E2E自动开跑。补英文README和中文runbook/性能§12收口，commit `fix(vps-edge): guard shared nginx deployment compatibility`。
- [ ] phase3全分支review：要求覆盖非root权限、回滚lease、hook副作用、release选择和秘密输出，发现问题修复后重跑对应fullsuite；关联#67提PR，CI绿后合并。不把旧genericCD的Vault迁移问题顺手夹进此PR。

### Task 3: 受控部署、验证与归档

- [ ] 明确维护时机/并发配置核对；从main确认phase1/2/3均合并，已知live hashes仍匹配、targetTLS/DNS正常、KV可用、磁盘足够容纳完整备份+试解包。创建含selector的 **draft Release**（`gh release create <tag> --draft --target <merged-sha>`）；draft不得触发部署，未确认窗口不发布。
- [ ] 用draft对应tag workflow_dispatch `edge_action=check`，审阅Tofu plan只新增预期output；正常auth/DB job必须显示skipped。失败停在此处，不在本机绕过CD修正。check通过后 `gh release edit <tag> --draft=false` 触发正式CD，tag/代码SHA不能变化。
- [ ] CD prepare：验证官方包/非root配置、完整备份试恢复、DNS证书reconfigure/dry-run、root-only staging/新user；此过程维护窗口尚未开始；失败恢复预检影响并停。KV初始写入的允许影响仅新名称，不能轮换已有app密钥。
- [ ] CD activation + watchdog：旧脚本移出活动路径、核心/service接管、共享Nginx处理器切换、并行critical probes，60s内未提交则恢复，记录实测用时。清理旧活动路径/45575规则时不删备份、不碰其他UFW规则。单次成功后不为“确认一下”再次重启服务。
- [ ] 通过新入口执行本机IPv4/IPv6 REALITY代理请求（私有临时client，测试后结束进程）；runner经公网A完成相同代理与Web探测，若runner无IPv6明确pending；交付私有client文件给desmond。用户网络最终连通需要用户客户端验证，未验证不写“全部完成”。
- [ ] 核对existing11域/7health/证书fingerprint/WebSocket与DERP握手、source IP、非rootservice、端口、日志轮转、证书installer/scheduler及脚本残留。VS记录只GET核实DNS-only；不要为制造“配置完成”而做无意义DNS写入。
- [ ] ~/plans回填真实backup/client路径、release/PR/issue、测试命令/退出状态、维护实际秒数、未完成项和§12性能结论；gitleaks无泄露后commit/push。repo plans/README同步；不存在~/Notebook则明确无需同步。外部验收后完成#67并清理已合并无修改worktrees/测试stack，不删除生产备份。

## Performance gate / rollback scope

生产路径触发网关/外部调用/调度门禁：端口/FD/timeout/日志轮转采用spec精确值；所有16项结论必须记录，after对比用同口径。无DB/批写/缓存新路径，不伪造p95或并发承诺。失败恢复以本次完整backup/journal为准，只有已审计CD restore可操作现场；若无法在预算内恢复，报告事故并停止后续删除，不静默扩大范围。

# VPS-edge 备份与限时恢复 Implementation Plan

> 历史计划，草稿未发布、未安装为生产管理框架。最终仅本机迁移及Android验收见[final-state.md](./final-state.md)，不要继续本计划的项目开发。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供可复测、默认不激活的宿主机事务处理器，证明配置漂移和失败能安全阻断/恢复。
**Architecture:** 标准库 Python 分离文件校验、备份、续期和事务状态机；root systemd oneshot 激活单元 + 独立 watchdog 在 CD 会话丢失时仍能恢复。本阶段只在隔离测试环境执行，没有生产入口。
**Tech Stack:** Python 3.12 unittest、GNU tar ACL/xattr、systemd、flock、Certbot 5.8、Podman。
**Spec:** [spec.md](./spec.md)；依赖 [phase 1](./implementation-phase-1.md) 已合并；[umbrella#67](https://github.com/desmondc9/signal-align-umbrella/issues/67)。

## Global Constraints

- 采用 phase 1 的 manifest/credential/API，不改端口/协议。生产激活仅 CD，SSH 22 控制通道保持不动。
- 原始备份 `/var/backups/sing-box-migration/<tx-id>/`，root 0700/0600；保留至少 30 天，不上传 artifact、不自动删除。
- 备份与预检均 T0 前；T+30s active、T+60s 未通过则回滚、T+120s 总恢复预算；不保证异常环境绝对 RTO。
- 只停止/启动 Nginx 与 sing-box；不操作 auth containers/DB/LibreChat/OpenClaw，不执行 233boy uninstall，不授予新 Azure 权限。
- ≤3 points/一天，分支 `feature/singbox-vps-edge-transaction`，独立 worktree；阶段内不触发生产 Release。

## Review Focus

1. 备份遗漏 auth symlink 的外部目标或权限，恢复后无效；Task 1 archive 完整性测试。
2. 调查后配置被人修改，部署不能覆盖；Task 1 drift/allowlist 测试。
3. 激活 controller 卡死或 SSH 消失，仍能限时恢复；Task 3 watchdog 故障注入。
4. 正常提交与 watchdog 同时触发不能把已提交配置回滚；Task 3 原子 commit/race 测试。
5. Certbot dry-run 调用 derper deploy hook或旧 nginx installer；Task 2 无副作用测试。

## Files / boundaries

| 路径 | 职责 |
|---|---|
| `scripts/vps_edge/{inventory,backup}.py` | 精确文件 allowlist、哈希/权限/链接目标、归档与恢复校验 |
| `scripts/vps_edge/renewal.py` | 三 lineage DNS reconfigure、单调度和限时预检 |
| `scripts/vps_edge/{transaction,health}.py` | journal 状态机、受限服务操作、deadline 健康检查 |
| `scripts/vps-edge-host.sh` | root CLI 入口，参数校验，不 eval、不 shell 拼接秘密 |
| `scripts/tests/vps_edge/test_{backup,renewal,transaction,health}.py` | temp filesystem/fake commands/fake clock 测试 |
| `local/vps/edge/tests/*` | 扩展隔离环境的真实恢复与客户端契约检查 |

## Interfaces

继续采用 phase 1 的 `EdgeCredentials`/manifest。`FileRecord` 字段：`path:str,kind:Literal[file,symlink,directory],sha256:str|None,link_target:str|None,uid:int,gid:int,mode:int`；path 必须在显式 allowlist，所有解引用目标单独列出；空 hash 只允许目录，不能表示「任意文件」。

`capture_inventory(root:Path)->list[FileRecord]`；`verify_drift(root:Path, expected:list[FileRecord], desired:list[FileRecord])->None` 接受已知原始或已知目标状态，其余抛错；`create_backup(root:Path,dest:Path,records:list[FileRecord])->BackupManifest`；`verify_backup(dest:Path)->None`；`restore_backup(root:Path,dest:Path)->None`。生产 root 为 `/`，测试 root 为 TemporaryDirectory，不能利用测试 root 绕过绝对路径 allowlist。

`HealthReport`：`ok:bool,checks:list[dict{name,ok,category}],pending:list[str]`，不得包含响应正文/凭据。`probe_all(manifest:dict,baseline:dict,deadline:float)->HealthReport` 使用 monotonic deadline，并发最多 8，单 probe connect 2s、total 5s；baseline 来自本次动态采集（证书 fingerprint），状态仍必须符合 spec 已确认值；发生漂移先解释并确认，不自动改预期。

事务 journal：`schema_version=1,tx_id,release_sha,phase,backup_dir,started_monotonic,credential_version,previous_release_sha`；phase 枚举 `prepared|activating|committed|restoring|restored|failed`。journal/manifest 只有元数据，真实值在受限配置文件。`prepare(root,staging,release_sha)->tx_id`；`activate(tx_id,ops,clock)->HealthReport`；`restore(tx_id,ops)->None`；`commit(tx_id)->None`。`ops` 为可替换的文件/命令执行适配器，fake ops 记录 argv 和 FS 结果，禁止调用真实 service manager。

CLI：`vps-edge-host.sh check STAGING`（只校验候选，不修改活动路径）、`prepare STAGING RELEASE_SHA`、`activate TX_ID`、`restore TX_ID`。tx-id 只能为 UTC 时间+随机 hex，禁绝路径分隔符/任意 unit 名。

### Task 1: 文件漂移与真实可恢复备份

- [ ] 写 `test_backup.py`：完整包含 sing-box 树、两个命令链接、vendor/local unit/drop-ins/enabled 状态、Nginx 树及 auth 外部链接目标、LE 树、Certbot 调度、UFW 用户规则；试恢复后校验内容、uid/gid/mode、links；损坏/缺文件/越界 symlink/异常 archive member 均拒绝；未知 live hash 不可覆盖。
- [ ] 运行 `python3 -m unittest discover -s scripts/tests/vps_edge -p test_backup.py -v`，确认未实现失败。
- [ ] 实现 inventory/backup API，以 GNU tar 保留 ACL/xattrs/numeric owner；生成限制访问的校验清单，archive 不打印内容，试解包仅在受限 staging。生产备份须先于任何续期状态修改，因此 prepare 首先备份再运行续期预检；失败可以恢复这些预检写入。
- [ ] 重跑测试；隔离环境执行真实 archive → damage fixture → restore → compare。未经 root 环境不得把 uid/gid 测试标假通过；可用 rootful 独立 test container完成。
- [ ] commit `feat(vps-edge): add verified backups and live drift guards`。

### Task 2: 续期迁移与无业务副作用的预检

- [ ] 写 `test_renewal.py`：仅处理 bandwagon/derp/headscale 的 lineage，不改证书 SAN/path；重配置为 dns-cloudflare、installer null，不传 --run-deploy-hooks，临时禁目录 hooks；系统 timer/旧 cron 仅在全部 DNS profile 有效后停用；03:00 命令同样获取 host lock并 nginx -t 后 reload；任何 dry-run 失败阻断 activate。
- [ ] 确认测试红；用 `/opt/certbot-dns/bin/certbot --help all` 或安装包源码核实 `reconfigure --cert-name ... --authenticator dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini --installer null --non-interactive --no-directory-hooks` 的实际支持。缺参数/插件就停止本任务，不能改成强制生产签发或手写一个未验证 renewal profile。
- [ ] 实现 `migrate_renewals(root:Path,run:CommandRunner)->None` 和 `validate_renewals(...)`；命令 argv 固定、每 lineage 最长 180s、DNS 凭据只引用路径。重配置及另一次逐证书 dry-run 使用 staging CA，保留已签发链，核对旧 installer 确实被移除；任何无法可靠去除旧 installer 的情况明确阻断。
- [ ] 在 fake 命令和隔离 Certbot fixture 中验证参数/保存状态；现场真正 reconfigure/DNS challenge 只在 phase 3 CD 的 prepare 步骤做。检查 derper PID/证书 fingerprint 未因 dry-run变化。重新跑同测试通过。
- [ ] commit `feat(vps-edge): preflight dns renewal without service hooks`。

### Task 3: 有限时 watchdog 的激活/恢复状态机

- [ ] 写 `test_transaction.py` 与 `test_health.py`：prepare 校验失败不触碰 active；正常 T<60s commit；启动失败/健康失败/子进程挂住/SSH parent退出触发 restore；丢失 commit 回包不重复切换；重复 release 幂等；watchdog 与 commit 竞态只有一个终态；恢复到原先 enabled/active 状态和精确 UFW 规则；不能调用 docker/compose、openclaw、derper restart。
- [ ] 运行 `python3 -m unittest discover -s scripts/tests/vps_edge -p 'test_*.py' -v`，定位预期红测，避免依赖真实生产 systemctl。
- [ ] 实现 API：以 `/run/lock/vps-edge.lock` 互斥正常部署/续期/prepare；journal 原子 rename+fsync；before T0 给独立 systemd watchdog 单元预置 restore；activation 使用唯一命名单元，TimeoutStartSec=55s/TimeoutStopSec=5s，watchdog 到 deadline 先终止该命名单元释放锁再恢复。只接受本 tx 生成的 exact unit名，不能 kill任意进程；watchdog不依赖 SSH。
- [ ] 在 active 前二次校验 drift、备份、端口、证书；创建非登录用户和受限目录，切换核心/配置/服务/Nginx，删除旧脚本前确认备份通过。健康 checks 并行包含 11 域、7 health、证书、来源语义/监听和本机代理；只在统一 deadline 内通过才写 committed 并解除 watchdog。旧残留/UFW 清理失败仍可恢复，未完成不能标最终成功。
- [ ] 扩展隔离 test systemd harness 测试正常、启动失败和 controller SIGKILL 三个场景；未具备可运行 systemd 的 sandbox 就作为 blocker，不在真实宿主机做故障注入。不执行用户业务 E2E。
- [ ] 全 unit/contract suite 绿；`shellcheck scripts/vps-edge-host.sh`；commit `feat(vps-edge): add deadline-bound activation and rollback`，关联 #67 提 PR，无生产 release。说明 §12 门禁的超时、日志轮转、watchdog/锁预算及已测故障情形。

## Phase handoff

phase 3 调用本阶段 root CLI，通过 release SHA 与 tx-id驱动，不能复制另一个简化版部署/回滚实现。默认 CLI 不自动部署；所有秘密仅从受限 staging 文件消费，失败日志只输出类别。

# NATS JetStream 单节点部署调研报告（供 reading-app 领域事件选型）

- **调研日期**：2026-11-05（所有版本号、日期、链接均当日核实）
- **目标机器**：搬瓦工 VPS，Ubuntu 24.04.4 LTS x86_64，8G 内存 / 6 CPU / 160G 磁盘（已用 65G），当前内存已用约 1.5G；本机容器工具为 podman 4.9.3（无 docker）
- **用途**：单节点 nats-server + JetStream 作为 reading-app 的领域事件中间件；应用发事件到 subject，消费端用 durable consumer 消费；将来其他 VPS 上的客户端/服务也要接入
- **对照报告**：`/home/desmond/docs/kafka-kraft-single-node-setup-research.md`（Kafka KRaft 单节点方案），最终在 Kafka 与 NATS 之间二选一

## 来源异常与说明（务必先读）

1. **docs.nats.io 已全站改版**为新结构（Concepts / Learn / Operate / Reference），旧的 `/running-a-nats-service/...` 路径会跳转到新章节（如 `Learn → Deployment & Upgrades`）。本报告全部抓取自新结构页面；docs.nats.io 每页支持在 URL 后加 `.md` 直接取 Markdown 原文，抓取的就是原文。
2. **packages.nats.io 当日无法访问**（连接失败）。当前官方安装文档（Getting Started、Download 页）也**不再提及任何 apt/yum 仓库**，官方安装路径只剩：`binaries.nats.dev` 安装脚本、GitHub Releases 二进制/`.deb`/`.rpm`、Docker 镜像。(来源: https://docs.nats.io/nats-server/installation 、https://nats.io/download/ 、packages.nats.io 连接失败实录 2026-11-05)
3. **nats.io 站点页脚仍写着 "CNCF incubating project"，属于滞后**：CNCF 官网项目页明确 NATS 已于 **2026-11-02 升级为 Graduated（毕业）**。本报告以 CNCF 官方页面为准。(来源: https://www.cncf.io/projects/nats/ 、https://nats.io/about/ 页脚)
4. GitHub API 为未认证抓取，个别响应过长被截断存储后已本地完整解析（jq），不影响结论。
5. 夜间构建镜像发布在 Docker Hub 的 `synadia/nats-server` 命名空间；**GitHub 上不存在 `synadia/nats-server` 或 `synadia-io/nats-server` 仓库**（API 404，当日核实）。不要把它当成"代码分叉"。

---

## A. 版本、治理与安装

### A.1 最新版本与治理现状（2026-11-05 核实）

| 组件 | 最新稳定版 | 发布日期 | 备注 |
|---|---|---|---|
| nats-server | **v2.15.2** | **2026-10-26** | nats-io 组织，Apache-2.0，最近 push 2026-11-04（活跃） |
| nats CLI（natscli） | **v0.5.1** | 2026-10-26 | nats-io/natscli，附带各平台 `.deb`/`.rpm`/zip 资产 |
| nats-py | v2.16.0 | 2026-09-16 | Python asyncio 官方客户端 |
| nats.go | v1.55.0 | 2026-10-23 | Go 官方客户端 |

(来源: https://api.github.com/repos/nats-io/nats-server/releases/latest 、https://api.github.com/repos/nats-io/natscli/releases/latest 、https://api.github.com/repos/nats-io/nats.py/releases/latest 、https://api.github.com/repos/nats-io/nats.go/releases/latest 、https://api.github.com/repos/nats-io/nats-server （许可证 Apache-2.0，pushed_at 2026-11-04）)

**治理现状（用户重点问题，逐条核实）**：

- **nats-io/nats-server 仍是唯一官方代码仓库且活跃**：v2.15.2（2026-10-26）发布，仓库 21k stars，Apache-2.0，未归档。(来源: https://github.com/nats-io/nats-server )
- **不存在 `synadia/nats-server` GitHub 仓库**（当日 API 404）。`synadia/nats-server` 只是 Docker Hub 上的 **nightly（每夜构建）镜像命名空间**，官方明确说明这些镜像"由上游 NATS 项目代码构建，不包含任何 Synadia 专有功能"。稳定版官方镜像仍在 `docker.io/library/nats`。(来源: https://nats.io/about/ （Roadmap 一节）、https://hub.docker.com/r/synadia/nats-server 、https://hub.docker.com/_/nats )
- **CNCF 关系：没有"出走"，反而升级了**。NATS 2018-03-15 以 Incubating 级别加入 CNCF，**2026-11-02 升为 Graduated（毕业项目）**——就在本次调研前 3 天。(来源: https://www.cncf.io/projects/nats/ )
- **许可证**：nats-server 与全部官方客户端均为 Apache 2.0。(来源: https://nats.io/about/ （"NATS server and its clients are open source under the Apache 2.0 license"）、GitHub API license 字段)
- **"官方发行版"指什么**：nats-io GitHub Releases 的二进制/`.deb`/`.rpm`（v2.15.2 附 `nats-server-v2.15.2-amd64.deb`、`-rpm`、`linux-amd64.tar.gz` 及 SBOM）、`binaries.nats.dev` 安装脚本、`docker.io/library/nats` 稳定镜像。(来源: https://github.com/nats-io/nats-server/releases/tag/v2.15.2 资产清单、https://docs.nats.io/nats-server/installation 、https://nats.io/download/ )
- **Synadia 与开源版的功能边界**：开源版即全功能 nats-server；Synadia 的商业产品是 **Synadia Cloud（全托管多云 NATS 平台）与企业支持**，下载页将其列为"连接器/服务"而非服务端分叉；roadmap 明确新特性进入上游开源仓库，nightly 镜像也是上游代码。官方 Helm chart 由 Synadia 团队维护（Bitnami NATS chart 2025-08 弃用后官方建议迁移过去）。(来源: https://nats.io/download/ （Synadia Cloud 条目）、https://nats.io/about/ 、https://nats.io/blog/bitnami-helm-charts-deprecated/ )
- **发布节奏**：官方博客确认已转向约 6 个月一个 minor：2.12（2025-09-22）→ 2.14（2026-04-30）→ 2.15（2026-09-17）；docs 的 Release Notes 下拉只提供 2.15/2.14/2.12/2.11 四档。(来源: https://nats.io/blog/nats-server-2.12-release/ 、https://nats.io/blog/nats-server-2.14-release/ 、https://nats.io/blog/nats-server-2.15-release/ 、https://docs.nats.io/ 页首版本选择器)
- **不确定项（明说）**：nats.io 站点页脚的 "incubating" 与 CNCF 页面的 "Graduated" 不一致，判定为官网文案滞后；未发现任何"Synadia 收回 nats-server"的官方公告或仓库迁移迹象。

### A.2 nats-cli 与 nats-box

- `nats` CLI 最新 **v0.5.1**（2026-10-26），单二进制，release 附带 `nats-0.5.1-amd64.deb` 等资产；安装脚本 `curl -sf https://binaries.nats.dev/nats-io/natscli/nats@latest | sh`。(来源: https://api.github.com/repos/nats-io/natscli/releases/latest 、https://docs.nats.io/nats-server/installation )
- `nsc`（账号/用户 JWT 工具）功能已并入 CLI 的 `nats auth` 命令族（安全文档全部用 `nats auth ...` 演示）。(来源: https://docs.nats.io/learn/security.md 、https://docs.nats.io/learn/security/decentralized-auth.md )
- **nats-box 调试容器仍活跃**（仓库最后 push 2026-11-03，未归档），镜像 `natsio/nats-box`，内含 `nats`、`nsc`、`nats-top`、`nk` 四件工具。(来源: https://api.github.com/repos/nats-io/nats-box 、https://github.com/nats-io/nats-box （README）)

### A.3 Ubuntu 24.04 x86_64 安装方式逐一核实

| 方式 | 现状 | 说明 |
|---|---|---|
| 官方 deb/apt 仓库（packages.nats.io） | **不可用/已弃** | 当日连接失败；官方文档不再引用任何 apt 仓库 |
| GitHub Release `.deb` | ✅ 可用 | `nats-server-v2.15.2-amd64.deb`、`nats-0.5.1-amd64.deb`，`dpkg -i` 安装；官方文档称发行版附带 systemd unit（含加固版 `nats-server-hardened.service`） |
| `binaries.nats.dev` 脚本 | ✅ 官方推荐 | `curl -sf https://binaries.nats.dev/nats-io/nats-server/v2@latest \| sh`，配合手写 systemd |
| GitHub 二进制 tar.gz + 手写 systemd | ✅ 可用 | `nats-server-v2.15.2-linux-amd64.tar.gz` |
| Docker 官方镜像 | ✅ 可用 | `docker.io/library/nats`：tag 现状（2026-11-05 核实）`latest`、`2.15.2`、`2.15.2-alpine`、`2.15.2-scratch`、`2.15.2-linux`、`2.15.2-alpine3.22` 及 2.14.9 等；多架构（amd64/arm64/...），最后推送 2026-10-27 |
| nightly 镜像 | ⚠️ 非稳定版 | `synadia/nats-server:nightly`（Docker Hub），官方声明不含 Synadia 专有功能 |

(来源: packages.nats.io 连接失败实录、https://github.com/nats-io/nats-server/releases/tag/v2.15.2 资产清单、https://docs.nats.io/nats-server/installation 、https://hub.docker.com/v2/repositories/library/nats/tags/ 、https://nats.io/download/ 、https://docs.nats.io/learn/deployment/hardening.md （distribution 附带 unit 的说明）)

**podman 注意点（本机 4.9.3，无 docker）**：

- `podman run docker.io/library/nats:2.15.2` 完全可用（官方镜像即 OCI 镜像）；podman 下建议：数据卷显式挂载（`-v /var/lib/nats/jetstream:/var/lib/nats/jetstream`）、监控端口只绑回环（`-p 127.0.0.1:8222:8222`）、用 quadlet 或 systemd unit 管理重启而非 `--restart`。这些是 podman 通用实践，**NATS 官方文档没有 podman 专页**（明说）；官方容器文档入口是 Docker Hub `_/nats` 与 Getting Started 的 `docker run` 示例。(来源: https://docs.nats.io/nats-server/installation 、https://hub.docker.com/_/nats )
- 默认配置注意：官方镜像默认**未开 JetStream**（需 `-js` 或配置文件），且 `store_dir` 默认是 `/tmp/nats/jetstream`——容器场景必须显式设置并挂卷。(来源: https://docs.nats.io/reference/config/jetstream.md （store_dir 默认值）、https://docs.nats.io/nats-server/installation )

### A.4 systemd unit 最佳实践（官方）

官方 Hardening 文档给出了"发行版附带、应在其上修改"的加固 unit 要点（单节点同样适用，去掉 cluster 相关即可）：

- `LimitNOFILE`：每 stream 约 2 个 FD + 客户端 socket，官方示例 `800000`；
- 沙箱：`ProtectSystem=strict` + `ReadWritePaths=`（必须覆盖 JetStream `store_dir`）、`MemoryDenyWriteExecute=true`、`ProtectKernelTunables`、`ProtectProc=invisible`、`PrivateDevices`；
- `CapabilityBoundingSet=`（清空）+ `SystemCallFilter=@system-service ~@privileged ~@resources`；
- **内存控制官方口径**：`MemoryMax`（systemd 硬顶，低于工作集会被 cgroup OOM-kill）设在实际峰值之上；`GOMEMLIMIT`（Go 运行时软目标，只让 GC 更激进）设得比 `MemoryMax` 略低；官方示例 `MemoryMax=6G` + `Environment=GOMEMLIMIT=5500MiB`。**官方文档没有给 GOGC 的专门建议**（明说），只提 GOMEMLIMIT。(来源: https://docs.nats.io/learn/deployment/hardening.md )

---

## B. JetStream 配置与领域事件建模

### B.1 启用 JetStream：`jetstream {}` 块

最小启用：`nats-server -js` 或配置 `jetstream { enabled: true }`。关键字段（官方 Reference，2026-11-05 版）：

| 字段 | 默认 | 说明 |
|---|---|---|
| `store_dir` | `/tmp/nats/jetstream` | file 存储目录；生产必须改到独立数据目录 |
| `max_memory_store` | 可用内存的 75%（读不到时回落 256MB；受 GOMEMLIMIT 约束） | memory storage 总上限 |
| `max_file_store` | `store_dir` 所在盘可用空间的 75%（读不到时回落 1TB） | file storage 总上限；**必须钉在实际卷大小**，超配会导致"先收写入后失败" |
| `domain` | - | JetStream 域（leaf 场景隔离用，创建后不可改） |
| `sync_interval` | `2m` | 强制 fsync 间隔；`always` = 每写都 sync（吞吐下降） |
| `max_buffered_msgs` / `max_buffered_size` | 10000 / 128MB | 存储暂不可用时的服务端缓冲 |
| `encryption_key` / `cipher` / `prev_encryption_key` | - | 静态加密（默认 ChaCha20-Poly1305，可 AES-GCM），密钥建议 ≥32 字节、用环境变量注入 |

(来源: https://docs.nats.io/reference/config/jetstream.md 、https://docs.nats.io/learn/deployment/sizing-and-resources.md （75% 口径与钉死 max_file_store 的告诫）、https://docs.nats.io/learn/security/encryption.md （静态加密与密钥轮换）)

**file vs memory storage（官方口径）**：file 落盘、重启后还在，是订单/事件日志的正确选择；memory 更快但**重启即丢**，只适合可丢数据。storage 是整条 stream 的属性（不可混搭），且**创建后固定不可改**（改了报 `stream configuration update can not change storage type`）。(来源: https://docs.nats.io/learn/jetstream/surviving-node-loss.md 、https://docs.nats.io/learn/jetstream/policies.md )

### B.2 Stream 设计（领域事件场景）

**subject 通配符与命名**：`*` 匹配一段 token，`>` 匹配一或多段尾部 token。领域事件推荐 `reading.book.created` 这类 `<域>.<聚合>.<动作>` 点分命名，stream 用 `subjects: ["reading.>"]` 捕获整个域（官方示例即 `orders.>` + `orders.created` 风格）。`orders.*` 不会匹配 `orders.at.northpole` 而 `orders.>` 会——权限与捕获用 `>` 前缀更稳。(来源: https://docs.nats.io/concepts/jetstream.md 、https://docs.nats.io/learn/security/authorization.md （通配符语义）)

**三种 retention 官方定义与选择**（原文语义，逐条核实）：

| 策略 | 语义 | 适用 | 选择建议（官方） |
|---|---|---|---|
| `limits`（默认） | 消息只被 `max_msgs`/`max_bytes`/`max_age` 逼出，**消费/ack 完全不影响保留**；stream 是日志 | 审计日志、事件历史、可回放 | 领域事件事实的首选——晚加入的消费者、重读、回放都依赖"消费完仍在" |
| `interest` | 每条消息等到**所有 filter 覆盖它的 consumer 都 ack** 才删除；无人感兴趣的 subject 即刻丢弃 | 每条消息都要被多个服务各处理一次的扇出 | 注意：慢消费者会拖住清理，官方提醒"interest 仍需设 limits 兜底，且要盯消费者健康" |
| `workqueue` | **第一个 ack 即删除**，每条消息只交给一个消费者 | 任务队列（官方例子：发货工单） | 官方明确：**消费者 filter 不得重叠**（重叠直接拒绝创建，err 10099/10100）；要横向扩 worker 用"多 worker 共享一个 consumer"，不是多 consumer |

**retention 创建后锁定**：`limits ↔ interest` 允许互改（但立刻作用于已存消息，可能清掉历史）；**进出 `workqueue` 一律拒绝**（err 10052）。官方建议"把 retention 当作创建时固定，要换就建新 stream 迁移"。(来源: https://docs.nats.io/learn/jetstream/retention-policies.md （以上全部含错误码）)

**limits / discard / 去重**（字段与默认值核实自 API Reference）：

- `max_msgs`（-1 无限）、`max_bytes`（-1 无限）、`max_age`（0 无限，纳秒；CLI 用 `720h` 这类时长）、`max_msgs_per_subject`（-1 无限；通配 stream 的按 subject 保留上限，也是"每 subject 最新状态"类需求的基础）；三者任一触顶即逐出。
- `discard`：`old`（默认，删最老腾位置）或 `new`（**拒绝新发布**）；配 `discard_new_per_subject: true` 可把 new 语义落到每个 subject。
- `duplicate_window`：`Nats-Msg-Id` 发布去重窗口，**默认 2 分钟**；同一 ID 在窗口内重发返回原 sequence 且 `duplicate: true`，不重复落盘。窗口之外的重试仍会重复。
- 其他有用的：`compression: s2`（JSON 等重复 payload 压缩效果好）、`deny_delete`/`deny_purge`、`allow_direct`（高速直读）、`allow_atomic`/`allow_batched`（2.12/2.14 的新发布模式）、`persist_mode: async`（先 ack 后刷盘，**仅限 R1 file stream，会丢尾部**，官方明确"不适合订单日志"）。
- **创建后可改/不可改清单**：storage、persist_mode、retention(进出 workqueue) 创建时锁定；discard 可改；compression 可改但重启/换主后生效；consumer 侧 deliver/ack/replay policy 也是创建时锁定。(来源: https://docs.nats.io/reference/jetstream/api/stream/create.md （字段与默认值）、https://docs.nats.io/learn/jetstream/publishing.md （Nats-Msg-Id、默认 2 分钟、duplicate 语义、persist_mode 警告）、https://docs.nats.io/learn/jetstream/policies.md （可变性表）)

### B.3 Consumer 设计（durable pull + AckExplicit）

- **durable pull consumer + `ack_policy: explicit` = at-least-once**：这是官方文档的标准组合（概念页与深潜页均如此示范）。pull 有两种驱动方式：`fetch`（批量、有超时，循环由你控制）与 `consume`（客户端常驻连续流）；大多数长期 worker 用 consume。（**注意**：nats-py 目前没有 consume 助手，官方文档明确"nats.py drives a pull consumer with fetch, so a continuous flow is a fetch loop"——用 fetch 循环代替。）(来源: https://docs.nats.io/concepts/jetstream.md 、https://docs.nats.io/learn/jetstream/pull-consumers.md )
- **deliver policy（只决定"创建那一刻从哪开始"，创建后锁定）**：`all`（默认，从头回放——等价 Kafka `auto.offset.reset=earliest`）、`last`（只从最新开始）、`new`（只收创建之后到达的）、`by_start_sequence` / `by_start_time`（从某序号/某时刻，等价 Kafka 按时间戳 seek）、`last_per_subject`（每个 subject 的最新一条，KV watch 的基础）。官方特别提醒：`new` 只定义历史起点，**重启/重连后 durable 会从保存的位置继续（含积压）**，不要期望每次重启都跳到最新。(来源: https://docs.nats.io/learn/jetstream/policies.md 、https://docs.nats.io/learn/jetstream/reading-back.md 系列)
- **ack 相关参数（官方默认值）**：
  - `ack_wait` 默认 **30s**：未应答即重投。处理慢的任务用 `in_progress` 心跳续命，或调大；
  - `max_deliver` 默认 **-1（无限重投）**：建议设 5~10 并配合 term 处理毒消息；
  - `max_ack_pending` 默认 **1000**：在途未 ack 上限；**不要低于你的 batch 大小**，否则吞了吞吐；要严格顺序可设 1（代价是吞吐）；
  - `backoff`（线性/自定义序列）会**取代 ack_wait**：第一项就是第一次重投等待；
  - **JetStream 没有内置死信队列（DLQ）**：达到 max_deliver 的消息从该 consumer 停止投递（消息仍在 stream），官方补救是订阅 advisory `$JS.EVENT.ADVISORY.CONSUMER.MAX_DELIVERIES.<stream>.<consumer>`（`nats events --js-advisory` 可统一看）。(来源: https://docs.nats.io/learn/jetstream/acknowledgment.md 、https://docs.nats.io/learn/jetstream/delivery-and-acknowledgment.md )
- **四种应答**：`ack`（完成）、`nak`（失败重投，可带 delay——裸 nak 立即重投，临时故障务必带延迟）、`term`（毒消息终结，永不重投；limits stream 上消息本身仍留给别的 consumer，同时发 `$JS.EVENT.ADVISORY.CONSUMER.MSG_TERMINATED...` advisory）、`in_progress`（续 ack_wait 计时）。(来源: https://docs.nats.io/learn/jetstream/acknowledgment.md )
- **多应用各自 durable consumer 独立消费同一 stream（等价 Kafka 多消费组 + 独立回放）——官方原文确认**："Multiple consumers can read the same stream independently, each with its own position... The stream holds a single shared copy of every message and serves each consumer from where it left off"（三个 consumer 各自游标互不影响，同一份存储）。每个应用用自己的 durable 名（如 `reading-indexer`、`reading-notifier`），deliver policy 各自定（`all` 回放 / `new` 只管新事件），互不干扰。(来源: https://docs.nats.io/concepts/jetstream.md （Consumers 一节与动画说明）)
- **横向扩 worker**：同一 durable consumer 被多个客户端共享分摊工作（等价 Kafka 同组多成员）；单 consumer 吞吐不够时官方路径是"加 worker"或"按 subject 拆 stream"，**不是加副本**（副本不扩吞吐）。(来源: https://docs.nats.io/learn/jetstream/surviving-node-loss.md 、https://docs.nats.io/concepts/jetstream.md )
- **queue group / workqueue 的独占语义与限制**：Core NATS 的 queue group 是"同组负载均衡"；JetStream 侧对应物是 WorkQueue retention（首个 ack 即删、filter 不得重叠、不能多 consumer 看全量）。要"多个 consumer 各自看全量"就用 interest/limits，要"一组 worker 抢活"就"多 worker 共享一个 consumer"。(来源: https://docs.nats.io/learn/jetstream/retention-policies.md )

### B.4 投递语义官方口径

- **Core NATS = at-most-once**（不落地、不回放）；**JetStream = at-least-once**（存储 + ack 循环 + 重投）。这是官方概念页第一段的原话级表述。(来源: https://docs.nats.io/concepts/jetstream.md )
- **exactly-once 能力 = 组合而非承诺**：当前官方文档统一口径是 at-least-once；要逼近"恰好一次"用三层组合——①发布端 `Nats-Msg-Id`（stream 内 2 分钟去重窗口，PubAck 返回 `duplicate` 标记）；②消费端 `AckExplicit` + 幂等处理；③关键消息 **double ack**（`ack_sync`/`AckSync`/`DoubleAck`——ack 是请求-确认，等 server 确认落账，官方明说"当重复处理有害且无法幂等时用它，每条多一次 RTT"）。**没有跨 stream 事务**（与 Kafka 事务不可比，官方文档无此承诺）。(来源: https://docs.nats.io/concepts/jetstream.md 、https://docs.nats.io/learn/jetstream/publishing.md 、https://docs.nats.io/learn/jetstream/delivery-and-acknowledgment.md )
- **发布确认**：JetStream 发布返回 `PubAck`（stream + sequence + duplicate），是"已存储"的唯一凭证；`published ≠ delivered`（消费是另一回事）。CLI 要用 `nats pub --jetstream` 才能看到 PubAck。(来源: https://docs.nats.io/learn/jetstream/publishing.md )

### B.5 单节点 R1 与文件持久化的 fsync 语义（诚实部分）

- **R1 = 单副本单点**：官方措辞直白——"R=1 has no fault tolerance. Lose that one server and you lose the stream: every message and every consumer's position... R=3 is the production floor; R=1 belongs on a laptop"。单节点部署 = 接受这个风险，用备份对冲（见 D.2）。R3 在单机上无法创建（server 直接拒绝 `--replicas=3`）。(来源: https://docs.nats.io/learn/jetstream/surviving-node-loss.md )
- **断电会丢什么（官方口径）**："File storage doesn't sync every write to disk right away... A write can still sit unsynced after it gets a `PubAck`, long enough that an **OS crash** could lose it, no full restart required"——即 **PubAck ≠ 已 fsync**；filestore 依赖 OS 文件系统缓冲，服务端按 `sync_interval`（默认 **2 分钟**）周期性强刷；对意外断电敏感的数据可把 stream 级 sync 设为 `always`（每写即刷，官方明说会降吞吐），R1 场景这是唯一的强持久开关。进程正常退出（含 lame-duck）会 flush 落盘。(来源: https://docs.nats.io/learn/jetstream/surviving-node-loss.md 、https://docs.nats.io/reference/config/jetstream.md （sync_interval 语义）、https://docs.nats.io/learn/deployment/rolling-upgrades.md （lame-duck 会"shuts down its JetStream assets cleanly, flushing to disk"）)

---

## C. 安全与远程接入

### C.1 认证选项与推荐

官方认证体系（2026-11-05 文档结构）：

| 方式 | 形态 | 单机自托管评估 |
|---|---|---|
| username/password | 配置文件 `authorization { users: [...] }`，密码可存 bcrypt 哈希（`nats server passwd` 生成，明文会被启动告警） | **推荐起步**：最少活动部件，per-user 权限一样能配 |
| token | 服务器级共享密钥（`authorization { token: ... }`），**无法按用户区分**，官方定位"快速内部设置，别无他用" | 不推荐 |
| nkey | 配置里只存公钥，客户端持 seed 对 nonce 签名，**密钥不过线**；`nats auth nkey gen` 生成 | 推荐（可单独用，也可作为 JWT 体系底座） |
| **JWT 去中心化认证**（operator / account / user 三层 + `nats auth`） | server 只信任一个 operator JWT；账号签用户，用户连接时出示 JWT + 对 nonce 签名；支持 scoped signing key（角色级权限模板）、凭据过期（`--expire 720h`）、吊销（`user rm --revoke` + `account push` 即时断连） | **账号/用户多起来后值得切**：用户增删不用改 server 配置，权限进 JWT；代价是要管理 operator seed（丢失=无法再签账号，官方要求离线备份） |
| mTLS（`verify_and_map`） | 客户端证书即身份（SAN/DN 映射到 user） | 机器间互信场景很好；发证书的运维成本高于发 creds |
| auth callout | 外部服务决定认证 | 本场景不需要 |

(来源: https://docs.nats.io/learn/security/authentication-basics.md （user/password、bcrypt、token、nkey、明文告警）、https://docs.nats.io/learn/security/decentralized-auth.md （三层信任链、nonce 签名、scoped key、过期与吊销、operator seed 备份）、https://docs.nats.io/learn/security/encryption.md （verify_and_map）)

**per-user subject 权限（给不同 app/机器不同账号）**：在 `authorization.users[].permissions` 写 `publish.allow / publish.deny / subscribe.allow / subscribe.deny`。规则要点（官方）：**写了 allow 列表即默认拒绝其余一切**；`deny` 压过 `allow`；`publish: []` 不是封死（要用 `deny: [">"]`）；没写 permissions = 不限。JetStream 的管理 API 走 `$JS.API.>` 的 request——consumer 应用需要放行 `$JS.API.>`（至少 `CONSUMER.MSG.NEXT`、`CONSUMER.CREATE` 等子集）与 `_INBOX.>`，否则表现为"莫名其妙超时"（官方 pitfall）。JWT 模式下同样的 allow/deny 列表进 JWT，用 `nats auth user edit <user> <acct> --pub-allow "reading.>"` 编辑。(来源: https://docs.nats.io/learn/security/authorization.md （含 $JS.API 超时 pitfall、deny 优先、空列表陷阱）、https://docs.nats.io/learn/security/decentralized-auth.md )

### C.2 TLS

- 配置方式：顶层 `tls {}` 保护 client 口；cluster/gateway/leafnodes/websocket 各有独立 `tls {}` 子块（互相独立，别只配一个）。字段：`cert_file` / `key_file` / `ca_file` / `verify`（mTLS）/ `verify_and_map`（证书即身份）/ `handshake_first`（TLS 先行，兼容 `"300ms"` 渐进迁移）/ `timeout`（握手超时，Reference 默认 500ms）/ `min_version` / `cipher_suites` / `pinned_certs` 等。(来源: https://docs.nats.io/learn/security/encryption.md 、https://docs.nats.io/reference/config/tls.md （完整字段表）)
- **nats-server 是否内置 ACME/Let's Encrypt：没有**。当日的 TLS 配置 Reference 字段表（上表 18 个字段）与安全教程均无 `hosts`/autocert/ACME 选项；官方教程的做法是外部签好证书后放文件 + `cert_file/key_file`。**方案**：certbot（webroot/standalone/DNS-01）签 Let's Encrypt → 部署到 `/var/lib/nats/certs/` → `systemctl reload nats-server`（SIGHUP 会重读证书文件，官方明确"换证书 = 放新文件 + reload，不用重启；旧连接保持原会话，新握手用新证书"）。certbot renew 的 deploy hook 里加 reload 即可全自动。(来源: https://docs.nats.io/reference/config/tls.md （字段清单，无 ACME）、https://docs.nats.io/learn/deployment/hardening.md （SIGHUP 换证书）、https://docs.nats.io/learn/security/encryption.md )
- **TLS + 认证同时启用**：就是"顶层 `tls {}` + `authorization { users: [...] }`"同时存在；客户端 `tls://host:4222` + `--tlsca`（+ `--user/--password` 或 `--creds`）。注意证书 SAN 必须覆盖客户端实际拨打的地址（IP 或域名），否则握手失败。(来源: https://docs.nats.io/learn/security/encryption.md )
- 可选增强：JetStream 静态加密（`jetstream { key: $JS_KEY }`，ChaCha20-Poly1305 默认）。(来源: https://docs.nats.io/learn/security/encryption.md )

### C.3 端口与暴露面规划

| 端口 | 用途 | 暴露策略 |
|---|---|---|
| 4222 | client（应用/CLI） | 唯一需要对公网开的口，必须 TLS + 认证 |
| 8222 | HTTP 监控（`/varz` `/connz` `/routez` `/jsz` `/healthz`） | **绝不裸暴露**：明文 HTTP 且**默认无认证**，`/connz` 直接泄露用户名、subject、订阅与流量，`/varz` 泄露版本/内存/连接数。绑 `127.0.0.1:8222` + 防火墙 deny |
| 7422 | leafnode（hub 侧接叶子） | 只在启用 leaf 时开，配 TLS + credentials |
| 7222 | gateway（超集群） | 单节点不用 |
| 6222 | cluster route | 单节点不用 |
| 443/ws | WebSocket（浏览器/仅 HTTP 出口环境） | 按需，走 `websocket {}` 监听或反代终止 TLS |

(来源: https://docs.nats.io/learn/deployment/hardening.md （四端口定义 + `http: "127.0.0.1:8222"` + ufw 示例 + 8222 泄露内容清单）、https://docs.nats.io/learn/monitoring/monitoring-endpoints.md （"monitoring port is unauthenticated by default"、/connz 字段）、https://docs.nats.io/learn/topologies/leaf-nodes.md （7422 默认口）、https://docs.nats.io/learn/websocket.md )

### C.4 远程接入模式对比（给结论）

**a) 直连 4222（TLS + 认证）——本场景首选。** 远程 VPS 上的服务与中心 VPS 上的应用用完全一样的客户端库与 URL（`tls://nats.example.com:4222` + creds），无额外组件。JetStream 全部能力（stream/consumer 管理、pull、回放）原生可用。只要客户端能出网即可。(来源: https://docs.nats.io/learn/security/encryption.md （TLS 客户端连接）、https://docs.nats.io/concepts/jetstream.md )

**b) Leaf Node——特定场景才值得。** 官方定位：叶子是**只出站**连回 hub 的本地 NATS server，为"对端无法被拨入（工厂内网/纯 egress）"或"边缘要本地自治"设计；本地客户端只见叶子，hub 只见一条 leaf 链路（连接与地址空间都被折叠）。**JetStream 的定位（重点核实）**：leaf **不自动拥有自己的 JetStream**——不开 domain 时叶子会**延长 hub 的 JetStream**（在叶子上建 stream 可能落到 hub 上！）；要本地独立存储必须给叶子配自己的 `jetstream { domain: ... }`，跨 leaf 复制数据走 mirrors/sources。生产用法：remote 带 `credentials`（叶子身份）+ `account`（绑定账号，实现地址空间隔离）。断线时：core 消息按兴趣桥接、断线即停；叶子本地若有自己的 JS domain，本地流仍可用。(来源: https://docs.nats.io/learn/topologies/leaf-nodes.md （ outbound 语义、domain pitfall、account/credentials、7422）、https://docs.nats.io/learn/jetstream/mirrors-and-sources.md （跨域复制，文档索引）、https://docs.nats.io/reference/config/leafnodes.md （字段：host/port 默认 7422、advertise、remotes、dial_timeout 1s 等）)
**结论**：你的远程 VPS 如果只是"跑个服务收发事件"，直连即可，leaf 是多余的一层运维；仅当远程侧需要**断线本地缓冲/本地自治**或**收拢大量边缘客户端**时才上 leaf（并配独立 domain）。

**c) WebSocket——浏览器或"只有 HTTP 出口"的环境。** `websocket {}` 监听 + `wss://` URL，7 个 Tier-1 客户端中 6 个支持（Go/JS/TS/Python/Java/Rust/.NET，**C 不支持**）；CLI 也接受 `ws://`。可用 wss 走 leaf。无浏览器需求就不开（多一个暴露面 + 帧开销）。(来源: https://docs.nats.io/learn/websocket.md )

**d) WireGuard/Tailscale 私网。** NATS 对此无特殊组件：私网地址直接当 `nats://10.x.x.x:4222` 用，TLS/认证仍建议保留（纵深防御）。与 Kafka 报告的思路一致（私网省掉公网证书/端口暴露，但依赖各 VPS 的 overlay 网络运维）。官方文档无 WireGuard 专页（明说），这是通用网络层方案。(来源: 本节为组合结论，NATS 侧依据 https://docs.nats.io/learn/security/encryption.md ——任意可达地址均可作 server URL)

### C.5 有没有 Kafka "advertised.listeners 坑"？

**单节点直连：没有。** 客户端只认你给的 URL，服务端不广播别的地址。**多服务器场景才出现**：集群/leaf 下客户端会从 INFO 里学到其他节点地址，此时用 `client_advertise`（client 侧）与 `leafnodes.advertise`（leaf 侧）声明"对外如何联系我"，典型用于 NAT 后；leaf 还有 `no_advertise`。且官方说明了证书校验的配套规则：客户端在广播列表里看到 IP 时，会以"DNS 更新"对待——重连用该 IP 连接但仍以原 DNS 主机名做证书校验。**给这台单机的结论：不存在此坑；将来若长成集群/leaf，把 `client_advertise` 设为公网域名即可。**(来源: https://docs.nats.io/reference/config/client_advertise.md 、https://docs.nats.io/reference/config/leafnodes.md （advertise/no_advertise）、https://docs.nats.io/learn/security/encryption.md （IP 广播与证书校验规则）)

---

## D. 运维

### D.1 监控

- **HTTP 端点**（8222，默认无认证，绑 localhost）：`/varz`（进程/版本/连接数/`slow_consumers`）、`/connz`（按账号/用户/订阅过滤，`?acc=&subs=true&auth=true&sort=pending&limit=`）、`/routez`（集群路由，单节点无用）、`/jsz`（JetStream 状态：stream/consumer 计数、meta leader、按账号下钻 `?acc=&streams=true`；全量展开在资产多时会很慢，官方建议带 `acc` 过滤）。告警盯 `connections`（不是只增不减的 `total_connections`）与 `slow_consumers`。(来源: https://docs.nats.io/learn/monitoring/monitoring-endpoints.md )
- **`/healthz`**：给编排器/LB 的 200/503 探针；参数可收窄语义：`js-enabled-only`（JS 已启用）、`js-server-only`（本机 JS 健康）、`js-meta-only`、以及指定 `stream`/`consumer`、`account`、`details`。容器健康检查用 `.../healthz?js-enabled-only=true` 这类组合。(来源: https://docs.nats.io/reference/system/monitor/healthz.md （参数 schema）、https://docs.nats.io/learn/monitoring/monitoring-endpoints.md )
- **CLI**：`nats server report`（含 `nats server report jetstream`）、`nats stream info`、`nats consumer info`（看 lag/未 ack/重投）、`nats events --js-advisory`（advisories）。类 top 实时视图用独立工具 **nats-top**（nats-box 内置）。(来源: https://docs.nats.io/learn/deployment/rolling-upgrades.md （server report jetstream）、https://docs.nats.io/learn/jetstream/acknowledgment.md （nats events）、https://github.com/nats-io/nats-box )
- **Prometheus**：官方出口 **prometheus-nats-exporter**（nats-io 仓库，"The official NATS exporter for Prometheus"，支持多服务器、可嵌入 Go 程序），抓 8222 端点；配套 Grafana 与 `nats server check` 阈值告警在 Monitoring 章节有完整走法。(来源: https://nats.io/download/ （Connectors 表中 NATS Prometheus Exporter 条目）、https://docs.nats.io/learn/monitoring.md （章节地图）)

### D.2 备份恢复

- **在线快照（官方推荐路径）**：`nats backup stream <STREAM> <目录> --consumers`（含 consumer 配置与位点）；产物 = `backup.json`（配置/状态）+ S2 压缩归档（2.15 起为 `stream.arc.s2`，旧版为 `stream.tar.s2`）。恢复：`nats backup restore stream <目录>`（**必须原名恢复、目标 stream 不能已存在**；`--consumers` 备份的 consumer 连位点一起回来）。2.15 起可离线校验：`nats backup validate`、`nats backup info --subjects`。慢链路调 `--chunk-size 64k --window-size 1m` 防 408。(来源: https://docs.nats.io/learn/backup-recovery/stream-backup-restore.md )
- **store_dir 直接拷贝**：file storage 就是磁盘上的文件，**停机状态下的冷拷贝可行且完整**（配置+流+consumer 状态都在 store_dir）；**运行中热拷贝一致性无官方保证**，要在线备份就用上面的 backup API。R1 单节点是唯一副本，官方定位"快照=恢复点，mirror=恢复时间，身份密钥=第三件要备份的东西"——**别忘了备份 nats.conf、creds/JWT、nkey seed**（丢失 operator seed = 无法再签发账号）。(来源: https://docs.nats.io/learn/backup-recovery.md （三类保护物、memory stream 不能快照→file storage 是备份前提）、https://docs.nats.io/learn/security/decentralized-auth.md （operator seed 备份）)
- 单节点节奏建议：cron 每日 `nats backup stream READING_EVENTS` 到异机/对象存储 + 定期 restore 演练。

### D.3 升级

- **单节点滚动升级就是一次优雅重启**：`SIGUSR2` 进 lame-duck（关新连接 → 转移 leader（集群时）→ flush JetStream → 广播 `INFO ldm:true` 让客户端提前切换 → 分批断连）→ 换二进制 → start。官方滚动升级文档本身就是在演示**新旧版本混跑**（非 leader 先升、meta leader 最后），单机场景退化为"lame duck + restart"两步。配置变更更轻：SIGHUP reload（`systemctl reload nats-server`），多数 TLS/limits 项热生效，JetStream 的 `store_dir`/`domain`/加密项不可热改。(来源: https://docs.nats.io/learn/deployment/rolling-upgrades.md 、https://docs.nats.io/reference/config/jetstream.md （reload 限制）、https://docs.nats.io/learn/deployment/config-management.md （章节入口，SIGHUP 零断连）)
- 升 2.15 注意备份格式变化（`stream.arc.s2`），官方有专门迁移说明。(来源: https://docs.nats.io/release-notes/upgrade-to-2.15.md （由 backup 页引用）)

### D.4 内存与磁盘控制（8G 机器推荐组合）

- **默认值就是最大的坑**：`max_memory_store` 默认 75% 内存、`max_file_store` 默认 75% 可用盘——8G 机器上即 ~6G/数十 G 级别，全部按"机器只跑 NATS"假设。**必须显式钉死**：`max_file_store` ≤ 数据卷真实可用空间（官方 pitfall：超配的表现是"发布中途失败"而非启动告警）。(来源: https://docs.nats.io/learn/deployment/sizing-and-resources.md )
- `store_dir` 放独立目录（如 `/var/lib/nats/jetstream`），不要用默认 `/tmp/nats/jetstream`；每 stream 约 2 个 FD；`max_payload` 默认 1MB、`max_connections` 默认 64K（单机场景都够）。(来源: https://docs.nats.io/reference/config/jetstream.md （store_dir 默认）、https://docs.nats.io/learn/deployment/sizing-and-resources.md （FD、payload、connections）)
- **8G/6C/95G 可用盘的组合建议**：`max_memory_store: 512MB`（memory stream 本来就不用，纯兜底）；`max_file_store: 20GB`（领域事件日志的硬顶，留足系统余量且远小于剩余盘）；systemd `MemoryMax=2G` + `GOMEMLIMIT=1800MiB`（官方"GOMEMLIMIT 略低于 MemoryMax"法则，NATS 本体+缓冲用不到 2G，留 6G 给 reading-app 与系统）；对断电敏感再把关键 stream 的 sync 设 `always`。

### D.5 常用命令速查（v0.5.x 语法，当日核实）

```bash
# 上下文（免密钥进 shell history）
nats context add prod --server tls://nats.example.com:4222 --creds /etc/nats/creds/admin.creds
nats context select prod

# stream / consumer
nats stream add READING_EVENTS --subjects "reading.>" --storage file --retention limits --defaults
nats stream info READING_EVENTS          # State: Messages/Bytes/First/Last Seq/Consumers
nats stream edit READING_EVENTS --max-age 2160h --max-bytes 10G
nats consumer add READING_EVENTS reading-indexer --pull --deliver all --ack explicit --defaults
nats consumer info READING_EVENTS reading-indexer   # Ack Floor / Outstanding Acks / Redelivered
nats consumer edit READING_EVENTS reading-indexer --wait 30s --max-deliver=5 --max-pending=1000
nats consumer next READING_EVENTS reading-indexer --count 10 --ack --wait 2s

# 发布 / 订阅（--jetstream 才返回 PubAck）
nats pub --jetstream reading.book.created --header "Nats-Msg-Id:book-42-created" '{"book_id":42}'
nats sub "reading.>"

# 监控与事件
nats server report jetstream
nats server check jetstream            # JS/消费者健康阈值检查（Monitoring 章节）
nats events --js-advisory --no-srv-advisory          # JS 告警流（MAX_DELIVERIES 等）

# 备份
nats backup stream READING_EVENTS ./backups/reading/$(date +%F) --consumers
nats backup validate ./backups/reading/2026-11-05
```

(来源: https://docs.nats.io/concepts/jetstream.md （stream/consumer add 示例）、https://docs.nats.io/learn/jetstream/publishing.md （--jetstream/--header）、https://docs.nats.io/learn/jetstream/acknowledgment.md （consumer edit 参数、nats events）、https://docs.nats.io/learn/backup-recovery/stream-backup-restore.md （backup/validate）、https://docs.nats.io/learn/security/authentication-basics.md （context）)

---

## E. 客户端矩阵（JetStream 支持度，以官方清单为准）

**Tier-1 官方客户端**（7 个：Go、JavaScript/TypeScript、Python、Java、Rust、C#/.NET、C）。**JetStream 官方支持清单**（nats.io 下载页 "NATS JetStream Enabled Clients" 表）：

| 客户端 | JetStream | 备注（当日核实） |
|---|---|---|
| **nats.go**（Go，官方） | ✅ | v1.55.0（2026-10-23），新 `jetstream` API（`jetstream.New`/`StreamConfig`/`Consume`），最成熟 |
| **nats-py**（Python asyncio，官方） | ✅ | v2.16.0（2026-09-16），JS 自 v2.0.0；`pip install nats-py`（nkeys 需 `nats-py[nkeys]`）；无 consume 助手→fetch 循环；高层糖在新项目 Orbit（synadia-io/orbit.py） |
| nats.java（Java，官方） | ✅ | Getting Started 示例版 2.25.2（gradle/maven `io.nats:jnats`） |
| NATS.Net（C#/.NET，官方） | ✅ | `dotnet add package NATS.Net` |
| nats.js（Node，官方）/ nats.ws（WebSocket，官方） | ✅ | 浏览器走 nats.ws |
| nats.deno（Deno/TS，官方） | ✅ | 官方 JS 表在列 |
| nats.rs（Rust，官方） | ✅ | `async-nats = "0.47.0"`（Getting Started 示例版） |
| nats.c（C，官方） | ✅ | **无 WebSocket transport**（7 个 Tier-1 中唯一） |
| **nats.ex（Elixir）** | ❓ 不在官方 JS 表 | about 页列为官方客户端之一，但 JetStream 支持表未列——用 Elixir 前需自行验证（明说） |
| pure-ruby-nats（Ruby） | ✅（表内） | nats.rb（旧客户端）不在 JS 表 |
| PHP / Qt C++ / Dart / Zig / Tcl 等 | 表内有社区实现 | 非官方维护 |

(来源: https://nats.io/download/ （两个客户端表）、https://docs.nats.io/concepts/ecosystem.md 与 https://docs.nats.io/learn/websocket.md （Tier-1 与 C 无 ws）、https://github.com/nats-io/nats.py （v2.16.0、JS since v2.0.0、Orbit 说明)、https://github.com/nats-io/nats.go/releases/tag/v1.55.0 、https://docs.nats.io/nats-server/installation （各语言安装命令与示例版本号))

### E.1 Python（nats-py）最小样例：发布（含 Nats-Msg-Id 去重）+ durable pull 消费（ack/nak/term）

```python
# pip install "nats-py[nkeys]"   # nkey/JWT 认证才需要 extras
import asyncio, json, ssl
import nats
from nats.errors import TimeoutError

URL = "tls://nats.example.com:4222"   # 远程直连（TLS）；本机则 nats://127.0.0.1:4222

# --- TLS（自签 CA 时）---
# ssl_ctx = ssl.create_default_context()
# ssl_ctx.load_verify_locations("ca.pem")

async def publish():
    nc = await nats.connect(servers=[URL], user_credentials="/etc/nats/creds/reading-app.creds")
    js = nc.jetstream()

    # stream 幂等创建——示例为了自包含；生产上改由 admin/CLI 预建（app 账号不给 $JS.API 权限）
    # limits（max_age/max_bytes）建议用 `nats stream edit` 设置，单位以所用客户端库文档为准
    await js.add_stream(name="READING_EVENTS", subjects=["reading.>"], storage="file")

    event = {"book_id": 42, "title": "DDD", "ts": "2026-11-05T10:00:00Z"}
    # 关键：可重试的发布必须带稳定的 Nats-Msg-Id（业务 ID 而非随机数）
    ack = await js.publish("reading.book.created", json.dumps(event).encode(),
                           headers={"Nats-Msg-Id": "book-42-created"})
    print(f"stored stream={ack.stream} seq={ack.seq} duplicate={ack.duplicate}")
    await nc.drain()

async def consume():
    nc = await nats.connect(servers=[URL], user_credentials="/etc/nats/creds/reading-indexer.creds")
    js = nc.jetstream()

    # durable pull consumer：官方文档的 Python 模式 = 先 add_consumer 再 pull_subscribe_bind
    # deliver_policy="all" 从头回放；"new" 只收新事件（创建后锁定，只决定起点）
    from nats.js.api import AckPolicy, ConsumerConfig, DeliverPolicy
    await js.add_consumer("READING_EVENTS", ConsumerConfig(
        durable_name="reading-indexer",
        filter_subject="reading.>",
        ack_policy=AckPolicy.EXPLICIT,
        deliver_policy=DeliverPolicy.ALL,
        ack_wait=30, max_deliver=5, max_ack_pending=1000,
    ))
    sub = await js.pull_subscribe_bind("reading-indexer", stream="READING_EVENTS")
    while True:
        try:
            msgs = await sub.fetch(batch=10, timeout=5)   # 空批（超时）是正常现象
        except TimeoutError:
            continue
        for msg in msgs:
            try:
                event = json.loads(msg.data.decode())
                await handle(event)          # 业务处理
                await msg.ack()              # 成功 → 确认推进游标
            except TransientError:
                await msg.nak(delay=10)      # 临时失败 → 10s 后重投（勿用裸 nak）
            except ValueError:
                await msg.term()             # 毒消息（解析不了）→ 终结，不再重投
            # 长任务可周期性 await msg.in_progress() 续 ack_wait

asyncio.run(publish())
asyncio.run(consume())
```

（API 依据：`js.add_stream`/`js.publish(headers=)`/`js.pull_subscribe(durable=)`/`fetch(batch, timeout)`/`ack/nak(delay)/term/in_progress/ack_sync` 均见于官方文档 Python 标签页与 nats-py README；`Nats-Msg-Id` 头与 duplicate 语义、空 fetch 处理、nak 带延迟、term 语义见 JetStream 章节。来源: https://docs.nats.io/learn/jetstream/publishing.md 、https://docs.nats.io/learn/jetstream/acknowledgment.md 、https://docs.nats.io/learn/jetstream/pull-consumers.md 、https://github.com/nats-io/nats.py 、https://nats-io.github.io/nats.py/ ）

### E.2 Go（nats.go，新 jetstream API）最小样例

```go
package main

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
)

func main() {
	nc, err := nats.Connect("tls://nats.example.com:4222",
		nats.UserCredentials("/etc/nats/creds/reading-app.creds"))
	if err != nil { log.Fatal(err) }
	defer nc.Drain()

	js, err := jetstream.New(nc)
	if err != nil { log.Fatal(err) }
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// stream（幂等创建/更新）
	_, err = js.CreateStream(ctx, jetstream.StreamConfig{
		Name:     "READING_EVENTS",
		Subjects: []string{"reading.>"},
		Storage:  jetstream.FileStorage,
		MaxAge:   720 * time.Hour,
	})
	if err != nil { log.Fatal(err) }

	// 发布：可重试 → 必带 WithMsgID（Nats-Msg-Id）
	ev := map[string]any{"book_id": 42, "title": "DDD", "ts": time.Now().UTC()}
	b, _ := json.Marshal(ev)
	ack, err := js.Publish(ctx, "reading.book.created", b,
		jetstream.WithMsgID("book-42-created"))
	if err != nil { log.Fatal(err) }
	log.Printf("stored stream=%s seq=%d duplicate=%t", ack.Stream, ack.Sequence, ack.Duplicate)

	// durable pull consumer：常驻 consume（客户端自动维持 pull 请求）
	cons, err := js.CreateOrUpdateConsumer(ctx, "READING_EVENTS", jetstream.ConsumerConfig{
		Durable:       "reading-indexer",
		AckPolicy:     jetstream.AckExplicitPolicy,
		DeliverPolicy: jetstream.DeliverAllPolicy, // 从头回放；DeliverNewPolicy 只收新事件
		AckWait:       30 * time.Second,
		MaxDeliver:    5,
		MaxAckPending: 1000,
	})
	if err != nil { log.Fatal(err) }

	cctx, err := cons.Consume(func(msg jetstream.Msg) {
		var ev map[string]any
		if err := json.Unmarshal(msg.Data(), &ev); err != nil {
			_ = msg.Term()               // 毒消息：终结
			return
		}
		if err := handle(ev); err != nil {
			_ = msg.NakWithDelay(10 * time.Second) // 临时失败：延迟重投
			return
		}
		_ = msg.Ack()                   // 成功；关键场景用 msg.DoubleAck(ctx) 双阶段确认
	})
	if err != nil { log.Fatal(err) }
	defer cctx.Stop()
	select {} // 阻塞运行
}

func handle(ev map[string]any) error { return nil }
```

（API 依据：`jetstream.New`、`StreamConfig`、`js.Publish(ctx, subj, data, jetstream.WithMsgID(...))`、`CreateOrUpdateConsumer`、`cons.Consume(handler)`、`Ack/NakWithDelay/Term/DoubleAck`——全部来自官方文档 Go 标签页原文示例。来源: https://docs.nats.io/concepts/jetstream.md 、https://docs.nats.io/learn/jetstream/publishing.md 、https://docs.nats.io/learn/jetstream/acknowledgment.md 、https://docs.nats.io/learn/jetstream/pull-consumers.md ）

---

## F. 诚实的短板与 Kafka 对照

### F.1 概念等价清单（衔接上一份 Kafka 报告）

| Kafka | NATS JetStream | 等价程度 |
|---|---|---|
| topic + partitions | stream（subject 扇入，无分区概念） | 形似；JetStream 单 stream 单 leader 写，扩写吞吐靠拆 stream（官方明说 replicas 不扩吞吐） |
| consumer group | durable consumer（服务端保存位点） | **完全等价**：官方原文"多个 consumer 各自位置独立读同一 stream" |
| 同组多成员 | 多 worker 共享一个 durable consumer | 等价（共享 MaxAckPending 上限） |
| `auto.offset.reset=earliest/latest` | deliver policy `all` / `last` / `new` | 等价（但 deliver policy 创建时锁定、只决定起点） |
| 按时间戳/offset seek | `by_start_sequence` / `by_start_time` | 等价 |
| log compaction（key 最新值） | `max_msgs_per_subject` + `last_per_subject` / KV bucket | 等价能力由 KV 抽象承担（官方：KV watch 建立在 last_per_subject 上） |
| retention.ms / retention.bytes | `max_age` / `max_bytes` / `max_msgs` | 等价（limits retention 默认） |
| 提交 offset | ack（ack floor）/ double ack | 等价，double ack 额外给"确认已落账" |
| 重平衡 | 无（pull 由客户端驱动，无组协调器） | NATS 更简单；代价是 worker 数不自动分摊 partition |
| advertised.listeners 坑 | 仅集群/leaf 场景的 `client_advertise` | 单节点无此坑（见 C.5） |

(来源: 各行对应的官方页——https://docs.nats.io/concepts/jetstream.md 、https://docs.nats.io/learn/jetstream/policies.md 、https://docs.nats.io/learn/jetstream/retention-policies.md 、https://docs.nats.io/learn/jetstream/surviving-node-loss.md )

### F.2 什么场景会后悔选 NATS（逐条给依据）

1. **需要 Kafka Connect 生态**：NATS 官方连接器清单很短（Kafka 桥、Spark adapter、Redis 连接器、Spring binder 等，由 NATS Team/Synadia 或社区维护），没有等价 Connect 的百级连接器市场。(来源: https://nats.io/download/ （Connectors and Utilities 全表）)
2. **需要 Schema Registry / Avro/Protobuf 强契约工具链**：NATS 无官方 Schema Registry；消息体就是字节 + 原生 headers，schema 治理要自建（JSON + 应用层校验，或外挂 registry）。官方文档与下载页均无此组件（缺失即依据）。CloudEvents/Avro 只能作为 payload 约定使用，无官方工具链。
3. **跨流/读-处理-写原子事务**：JetStream 无跨 stream 事务；exactly-once 只是"Nats-Msg-Id 去重（2 分钟窗口）+ 显式 ack + double ack + 业务幂等"的组合拳。Kafka 事务性生产者/幂等读写的端到端 exactly-once 语义在这里没有对应物。(来源: https://docs.nats.io/learn/jetstream/publishing.md 、https://docs.nats.io/learn/jetstream/delivery-and-acknowledgment.md ——文档通篇 at-least-once 口径)
4. **超高吞吐、分区级水平扩展**：官方明说" replicas 不扩写吞吐；单 leader 是写的上限，扩吞吐靠按 subject 拆 stream / 加 worker"。Kafka 用分区把单 topic 写吞吐横向摊到 broker；JetStream 是"每 stream 一个写 leader"模型。(来源: https://docs.nats.io/learn/jetstream/surviving-node-loss.md )
5. **生态默认值**：大数据/流处理（Flink、Kafka Streams 类）对 Kafka 是一等公民；NATS 侧只有 Spark adapter、RisingWave/Flink 社区连接器等零星选项。(来源: https://nats.io/download/ )
6. **单节点 R1 + 断电**：PubAck 后仍可能有最长 `sync_interval`（默认 2 分钟）的未 fsync 窗口；Kafka 单 Broker 同样有刷盘语义问题，但 NATS 官方把这个窗口写得很明白（见 B.5）——对不可丢事件要么 `sync: always` 降吞吐，要么接受 RPO。

### F.3 单节点内存/磁盘实测口径

- **官方内存口径**："The server typically uses less than 20MB of RAM"——这是 nats.io About 页对 **server 本体（无负载、core 形态）**的表述。(来源: https://nats.io/about/ )
- **加 JetStream 后**：官方没有给"开 JS 后 X MB"的单个数字（明说）；官方 sizing 框架是：内存 = 连接 + 订阅 +（memory stream 数据），file stream 吃磁盘不吃内存；"几百个连接舒服地放进几百 MB"是官方文档给的量级；`max_memory_store`/`max_file_store` 默认 75% 的口径见 B.1。**对本机（8G、每 stream 两个 FD、reading-app 域事件量级）的现实预期**：空载 JS server 数十 MB 级，连接与缓冲涨到一两百 MB 量级，配 `MemoryMax=2G` + `GOMEMLIMIT=1800MiB` 有充足余量。(来源: https://docs.nats.io/learn/deployment/sizing-and-resources.md )

---

## G. 可直接落地的配置样例

### G.1 完整 `nats-server.conf`（单节点：JetStream + TLS + 多账号权限 + monitoring 仅 localhost）

```hocon
# /etc/nats/nats-server.conf —— reading-app 事件中枢（单节点 R1）
server_name: reading-hub-1

# ---- 客户端口：唯一对公网暴露的口（TLS + 认证）----
listen: "0.0.0.0:4222"

tls {
  cert_file: "/var/lib/nats/certs/server-cert.pem"   # Let's Encrypt: fullchain.pem
  key_file:  "/var/lib/nats/certs/server-key.pem"    # Let's Encrypt: privkey.pem
  ca_file:   "/var/lib/nats/certs/ca.pem"            # 私有 CA 时用；LE 证书可省略（客户端用系统根）
  timeout:   2
  # handshake_first: true   # 可选：TLS 先行（所有客户端需支持 --tlsfirst）
}

# ---- 监控：仅 localhost，明文无认证，绝不暴露公网 ----
http: "127.0.0.1:8222"

# ---- JetStream ----
jetstream {
  store_dir:        "/var/lib/nats/jetstream"  # 独立数据目录，勿用默认 /tmp
  max_memory_store: 512MB                      # 不用 memory stream，纯兜底
  max_file_store:   20GB                       # 钉在实际可用空间内（默认 75% 盘太危险）
  sync_interval:    "2m"                       # 断电敏感的关键 stream 可在 stream 级设 sync: always
  # key: $JS_KEY                               # 可选：静态加密（环境变量注入）
}

# ---- 认证 + per-user 权限（配置文件模式；账号多了换 nats auth/JWT）----
authorization {
  users: [
    # reading-app 本体：只许发领域事件（PubAck 回包走 _INBOX，即官方 order-svc 模式）
    { user: reading-app, password: "$2a$11$...(nats server passwd 生成)"
      permissions: {
        publish:   { allow: ["reading.>"] }
        subscribe: { allow: ["_INBOX.>"] }
      } }
    # 消费端（索引器）：拉消息 + 必要的 JS API 子集
    { user: reading-indexer, password: "$2a$11$..."
      permissions: {
        publish:   { allow: ["$JS.API.CONSUMER.>", "$JS.API.STREAM.INFO.>"] }
        subscribe: { allow: ["_INBOX.>"] }
      } }
    # 远程 VPS 上的服务：单独账号、最小授权示例
    { user: remote-svc-1, password: "$2a$11$..."
      permissions: {
        publish:   { allow: ["reading.book.imported"] }
        subscribe: { allow: ["reading.>", "_INBOX.>", "$JS.API.CONSUMER.MSG.NEXT.>"] }
      } }
    # 管理员（人/运维）：全权
    { user: admin, password: "$2a$11$..." }
  ]
}

# ---- 可选：WebSocket（浏览器才需要；默认不开）----
# websocket { listen: "0.0.0.0:443", tls { cert_file: "...", key_file: "..." }, same_origin: true }

# ---- 可选：Leaf Node hub（远程 VPS 需要"本地自治"时才开）----
# leafnodes {
#   listen: "0.0.0.0:7422"
#   tls { cert_file: "/var/lib/nats/certs/server-cert.pem", key_file: "/var/lib/nats/certs/server-key.pem" }
#   authorization { users: [ { user: leaf-remote-1, password: "..." , permissions: { publish: { allow: ["reading.>"] } } } ] }
# }

# ---- 优雅停机（升级/重启时不硬断客户端）----
lame_duck_grace_period: "10s"
lame_duck_duration:     "2m"
```

（各块语义与字段出处：TLS 与 cert 轮换 https://docs.nats.io/learn/security/encryption.md 、https://docs.nats.io/reference/config/tls.md ；http 仅 localhost https://docs.nats.io/learn/deployment/hardening.md ；jetstream 块 https://docs.nats.io/reference/config/jetstream.md ；users/permissions/bcrypt https://docs.nats.io/learn/security/authentication-basics.md 、https://docs.nats.io/learn/security/authorization.md （含 $JS.API 放行提醒）；leafnodes https://docs.nats.io/learn/topologies/leaf-nodes.md ；lame duck https://docs.nats.io/learn/deployment/rolling-upgrades.md ）

### G.2 systemd unit（按官方 hardening 模板裁剪的单节点版）

```ini
# /etc/systemd/system/nats-server.service
[Unit]
Description=NATS Server (JetStream, single node)
After=network-online.target
Wants=network-online.target

[Service]
User=nats
Group=nats
ExecStart=/usr/local/bin/nats-server -c /etc/nats/nats-server.conf
ExecReload=/bin/kill -s HUP $MAINPID      # 配置/证书热加载
# 升级时的优雅停机：先进 lame duck（SIGUSR2），再等 systemd 的 SIGTERM 收尾
ExecStop=/bin/kill -SIGUSR2 $MAINPID
TimeoutStopSec=150s                  # 必须 > lame_duck_duration（默认 90s 会中途 SIGKILL）

# 内存上限：GOMEMLIMIT 略低于 MemoryMax（官方法则）
Environment=GOMEMLIMIT=1800MiB
MemoryMax=2G

# 官方加固模板
LimitNOFILE=65536
ProtectSystem=strict
ReadWritePaths=/var/lib/nats
MemoryDenyWriteExecute=true
ProtectKernelTunables=true
ProtectProc=invisible
PrivateDevices=true
CapabilityBoundingSet=
SystemCallFilter=@system-service ~@privileged ~@resources
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

（模板出处：https://docs.nats.io/learn/deployment/hardening.md （unit 各指令、GOMEMLIMIT/MemoryMax 法则、ReadWritePaths 必须覆盖 store_dir 的 pitfall）；SIGUSR2 lame duck 出处：https://docs.nats.io/learn/deployment/rolling-upgrades.md 。注：`ExecStop` 用 SIGUSR2 后 systemd 仍会发 SIGTERM 结束进程，lame_duck_duration 要短于 TimeoutStopSec（默认 90s，可按需调））

### G.3 远程接入三方案客户端片段

**方案一：直连 TLS + 账号（首选）**

```bash
# 远程 VPS 上：context 一次性保存凭据
nats context add prod --server tls://nats.example.com:4222 \
  --user remote-svc-1 --password "$NATS_PASSWORD"
nats pub reading.book.imported '{"book_id":43,"src":"vps2"}'
```

```python
nc = await nats.connect("tls://nats.example.com:4222",
                        user="remote-svc-1", password=os.environ["NATS_PASSWORD"])
```

（来源: https://docs.nats.io/learn/security/encryption.md （tls:// + 凭据）、https://docs.nats.io/learn/security/authentication-basics.md （context））

**方案二：Leaf Node（远程侧要断线自治/收拢边缘时）**

```hocon
# 远程 VPS：leaf-nats.conf（轻量 nats-server，仅出站连回 hub）
server_name: reading-leaf-vps2
listen: "127.0.0.1:4222"          # 只服务本机/本网客户端
jetstream { domain: "vps2-local" } # 关键：不给 domain 会"延长 hub 的 JetStream"，本地建流会落到 hub！
leafnodes {
  remotes: [
    { urls: ["tls://leaf-remote-1:secret@nats.example.com:7422"]  # 配置文件认证模式（与 hub 的 leafnodes.authorization 对应）
      # credentials: "/etc/nats/creds/leaf-remote-1.creds"        # JWT 模式（hub 走 operator 模式时用）
      # account: "READING"                                        # 绑定账号，实现 subject 空间隔离（hub 侧需同账号）
    }
  ]
}
```

（来源: https://docs.nats.io/learn/topologies/leaf-nodes.md （remotes/credentials/account、domain pitfall 原文）、https://docs.nats.io/reference/config/leafnodes.md ）

**方案三：WireGuard/Tailscale 私网（最省暴露面）**

```bash
# hub 与远程 VPS 间已有 wg0（10.8.0.0/24）时：不开公网 4222，直接走私网
nats context add prod --server nats://10.8.0.1:4222 --user remote-svc-1 --password "$NATS_PASSWORD"
# 建议仍保留 TLS+认证（纵深防御）：server 监听改 tls:// 并对 wg 网段放行
```

（NATS 侧无专有组件，通用网络层方案；TLS/认证建议保留的依据同方案一）

### G.4 防火墙基线（hub 侧）

```bash
ufw default deny incoming
ufw allow 22/tcp
ufw allow 4222/tcp          # client（TLS+认证）
# ufw allow 7422/tcp        # 仅启用 leaf 时
ufw deny 8222/tcp           # 双保险（已绑 127.0.0.1）
```

（端口策略依据：https://docs.nats.io/learn/deployment/hardening.md （含官方 ufw 示例的等价写法））

---

## H. 针对这台机器的推荐方案（总结）

**安装方式（明确首选）**：**GitHub Release 的 `.deb`（`nats-server-v2.15.2-amd64.deb`）+ 自带/手写 systemd unit**，CLI 同样装 `.deb`（`nats-0.5.1-amd64.deb`）。理由：单进程常驻服务由 systemd 直接管理（lame-duck、SIGHUP reload、加固沙箱都是官方 runbook 的原生形态）；JetStream 数据卷是普通目录，备份/权限/监控最直接；避开容器的双层存储与 rootless 端口映射等额外变量。**不首选 podman 容器**：能用（`docker.io/library/nats:2.15.2` 镜像健康、多架构），但官方 systemd/hardening/备份 runbook 全部以主机进程为前提，容器化对本场景只增加间接层。若坚持容器：挂载 `/var/lib/nats/jetstream`、`-p 127.0.0.1:8222:8222`、显式 `-js` 与 store_dir。`binaries.nats.dev` 脚本适合快速起步，等价于二进制方式。

**nats-server.conf 关键参数**（数字给定）：`store_dir=/var/lib/nats/jetstream`；`max_memory_store=512MB`；`max_file_store=20GB`；`sync_interval=2m`（关键 stream 可 `sync: always`）；`http=127.0.0.1:8222`；4222 上 TLS+多用户；systemd `MemoryMax=2G` + `GOMEMLIMIT=1800MiB`；`LimitNOFILE=65536`。

**stream/consumer 推荐（reading-app 领域事件）**：

- Stream `READING_EVENTS`：`subjects=["reading.>"]`、`storage=file`、`retention=limits`（事件事实要可回放，官方"audit log → Limits"）、`max_age=2160h`(90d，按业务定)、`max_bytes=10GiB`、`discard=old`、`duplicate_window` 默认 2 分钟够用（重试间隔必须 < 2 分钟）、可选 `compression=s2`。任务型需求（如"导入作业"）另建 WorkQueue stream，filter 不重叠。
- Consumer：每应用一个 durable pull consumer（`reading-indexer`、`reading-notifier`...），`ack_policy=explicit`、`deliver_policy=all`（新应用从头回放）/`new`（只管新事件）、`ack_wait=30s`、`max_deliver=5` + 代码里 term 毒消息 + 订阅 `MAX_DELIVERIES` advisory、`max_ack_pending=1000`；需要严格顺序时单独建 `max_ack_pending=1` 的 consumer。
- 发布端纪律：可重试的发布一律带稳定 `Nats-Msg-Id`（如 `book-42-created`）。

**远程接入首选**：**直连 4222（TLS + 每机器/每应用独立账号 + per-user 权限）**；若两端本来就打算组 WireGuard/Tailscale，私网直连更省暴露面（TLS/认证仍保留）。Leaf node 仅在远程需要断线本地缓冲/本地自治时引入（记得独立 `jetstream.domain`）。WebSocket 仅浏览器需要时开。

**选 NATS 而不选 Kafka 的前提条件自检清单**（全部成立 → 放心选 NATS；任一不成立 → 回到 Kafka 报告）：

1. 事件量级是"单机轻松扛"（数千~数万 msg/s 以下），不需要分区级横向扩展写吞吐；
2. 不依赖 Kafka Connect 生态、Schema Registry、Kafka Streams/Flink 流处理管线；
3. 不需要跨 stream/跨聚合的原子事务（接受"Nats-Msg-Id 去重 + 幂等消费"的有效恰好一次）；
4. 单节点 R1 的可用性可接受（进程挂了 systemd 拉起、盘坏了从 `nats backup` 恢复，RTO=分钟级；不能接受则需要 ≥3 节点集群——那时 NATS 与 Kafka 的运维差距缩小）；
5. 接受 PubAck 后最长 `sync_interval`（默认 2m，可调 always）的断电丢失窗口；
6. 客户端语言在官方 Tier-1 清单内（Python/Go 都是一等公民；Elixir 需自行验证 JetStream 支持）；
7. 未来多 VPS 接入形态是"少量服务直连"而非"海量边缘节点"（后者才是 leaf/超集群的主场）。

**一句话**：reading-app 的领域事件场景（单 VPS、Python/Go 客户端、durable consumer 回放、跨 VPS 少量接入）恰好落在 JetStream 的舒适区——单二进制、无 ZooKeeper/KRaft、原生多消费组语义、官方 runbook 齐全（nats-server v2.15.2 / nats CLI v0.5.1 / CNCF Graduated 2026-11-02，全部 2026-11-05 核实）；它的代价是生态薄、无跨流事务、单 leader 写扩展上限，以及 R1 单节点必须靠备份纪律兜底。

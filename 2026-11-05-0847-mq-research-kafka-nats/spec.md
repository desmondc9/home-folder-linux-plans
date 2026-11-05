# MQ 选型调研：单节点 Kafka (KRaft) vs NATS JetStream

- 环境: Bandwagon VPS（Ubuntu 24.04.4 LTS x86_64，8G RAM / 6 vCPU / 160G 磁盘已用 65G；OpenJDK 21、podman 4.9.3 已装；端口 9092/9093/4222 空闲）。调研与未来部署均在这台 VPS 上。
- 日期: 2026-11-05
- 状态: 调研完成，选型倾向 NATS JetStream；实际部署为后续任务。

## 背景与目标

reading-app（本机 compose 部署的单容器 API + 前端 dist，镜像来自 `READING_BACKEND_IMAGE`，内部端口 8000，语言栈待确认）需要消息中间件投递领域事件：应用发事件到 topic/subject → 消费端消费处理；将来其他 VPS 上的服务也要接入这台中枢。调研两个问题：

1. 这台 8G/6C VPS 能否搭单节点 Apache Kafka（KRaft 模式，不用 ZooKeeper），远程接入怎么配？
2. 如果 Kafka 太重，更轻量的开源免费替代有哪些、各自适合什么场景？

## 范围

- In：Kafka KRaft 单节点可行性/内存/远程接入/安全（一手来源核实到 2026-11-05 最新版本）；NATS + JetStream 同维度对比；轻量替代盘点（Redpanda / RabbitMQ / Redis Streams / Valkey / Pulsar）；裸机 vs 容器部署形态。
- Out：实际部署与验证（后续任务）、多节点集群、性能压测。

## 关键结论

全部结论 2026-11-05 当天从官方一手来源（kafka.apache.org / cwiki KIP / docs.nats.io / nats-io GitHub / 各项目官网与许可证原文）核实，逐条带来源 URL，详见本目录两份报告。

### Kafka 侧（[kafka-kraft-single-node-setup-research.md](./kafka-kraft-single-node-setup-research.md)）

- 最新稳定版 **Kafka 4.4.0**（2026-10-22）；ZooKeeper 已在 4.0 彻底移除（仅 KRaft）；broker 要求 Java 17+（本机 OpenJDK 21 已满足，零依赖可装）。
- **跑得动**：官方脚本默认堆 1G，本机可压 768MB + G1GC，broker RSS ≈1.2–1.5G（Kafka 靠 OS page cache 而非大堆），8G 机器与其他服务共存余量充足；磁盘剩 84G 用 `log.retention.hours=72` + `log.retention.bytes` 兜底。
- 远程接入经典坑：`advertised.listeners` 必须是客户端可路由的公网 IP/域名（不能 0.0.0.0/内网 IP）；4.1+ 已改用 `controller.quorum.bootstrap.servers` + `format --standalone`（网上旧教程的 `controller.quorum.voters` 已过时）。
- 安全：绝不用无认证 PLAINTEXT 暴露公网；官方路径 SASL_SSL + SCRAM-SHA-512（格式化时 `--add-scram` 一步注入凭据），或 WireGuard/Tailscale 私网。
- 镜像：`apache/kafka` 官方镜像可用；`bitnami/kafka` 2025-08 起转 Photon 基底付费向 Secure Image，个人自托管勿再用。

### 轻量替代盘点（详见 Kafka 报告 B 节）

- **Redpanda 26.2**（BSL 1.1，自托管免费/禁转售）：官方生产要求**每核 ≥2G 内存**（单节点 4G 级）——比 Kafka 单节点还重，与"8G 机器共存其他服务"矛盾，排除。
- **RabbitMQ 4.4**（MPL 2.0）：普通队列 ack 即删，事件回放要绕道 Streams 功能，形态更适合任务队列。
- **Redis Streams / Valkey 9.1**：保留策略基于内存条数（无按时间/字节的磁盘保留），只适合短窗口事件流；Redis 许可证已变三重（8.0 起含 AGPLv3），Valkey 为 BSD 分叉。
- **Pulsar 5.0**：单节点要同时跑 broker + BookKeeper + 元数据存储三类进程，单机场景反而最重。

### NATS JetStream 侧（[nats-jetstream-single-node-setup-research.md](./nats-jetstream-single-node-setup-research.md)）

- **nats-server 2.15.2**（2026-10-26）+ nats CLI 0.5.1；Apache 2.0；**2026-11-02 CNCF 毕业（Graduated）**；`nats-io/nats-server` 是唯一官方仓库（无 Synadia 分叉，那只是 nightly 镜像命名空间）。
- Go 单二进制无外部依赖；官方 apt 仓库（packages.nats.io）已失效，**首选 GitHub Release `.deb` + systemd**（官方 hardening/备份/升级 runbook 均以主机进程为前提，容器化只增加间接层）。
- 内存：官方 "<20MB" 指空载 core server；开 JetStream + 负载后一两百 MB 量级；推荐 systemd `MemoryMax=2G` + `GOMEMLIMIT=1800MiB` 兜底。
- 领域事件建模：Stream `READING_EVENTS`（`subjects=["reading.>"]`、file storage、limits retention、`max_age=90d` + `max_bytes=10GiB`）+ 每应用一个 durable pull consumer + `AckExplicit` = at-least-once；**多 durable consumer 各自独立游标读同一 stream，完全等价 Kafka 多消费组 + 独立回放**（官方原文确认）；发布端带 `Nats-Msg-Id`（默认 2 分钟去重窗口）+ double ack + 业务幂等逼近 exactly-once。
- 远程接入**首选直连 4222（TLS + 每机器/每应用独立账号 + per-user subject 权限）**；单节点**没有** Kafka 的 advertised.listeners 坑；Leaf Node 仅远程需要断线本地自治时用（且必须配独立 `jetstream.domain`，否则本地建流落到 hub）；WebSocket 仅浏览器场景。无内置 ACME——certbot + SIGHUP 热加载。
- 必须钉死的默认值（默认即地雷）：`max_file_store` 默认=盘可用空间 75%（应设 20G）、`store_dir` 默认 `/tmp`（应改 `/var/lib/nats/jetstream`）、监控口 8222 明文无认证（只绑 127.0.0.1）。
- 诚实短板：无 Kafka Connect / Schema Registry 生态等价物；无跨 stream 事务；无内置 DLQ（`max_deliver` + `term` 毒消息 + `MAX_DELIVERIES` advisory 补）；R1 单节点官方原话 "R=1 belongs on a laptop"——PubAck ≠ 已 fsync，默认 `sync_interval=2m` 的断电丢失窗口（关键 stream 可 `sync: always` 降吞吐）。

## 决策

**倾向 NATS JetStream**（reading-app 场景：单 VPS、领域事件量级、durable consumer 回放、少量 VPS 接入、Python/Go 客户端均为 Tier-1）。NATS 报告 H 节的 7 条"选 NATS 而不选 Kafka"自检清单全部命中。反转条件（任一出现则回到 Kafka 报告）：需要 Kafka Connect 生态、Schema Registry、跨 stream 原子事务、分区级写吞吐扩展。

## 风险与缓解

- R1 单点：进程挂由 systemd 自动拉起；数据靠每日 `nats backup stream <STREAM> --consumers` 异机归档 + 定期 restore 演练；升级走 lame-duck 优雅重启。
- 断电丢 2 分钟窗口：不可丢的关键 stream 设 `sync: always`（接受吞吐下降）。
- 8222 监控口泄露（`/connz` 暴露用户名/subject）：只绑 `127.0.0.1` + ufw deny 双保险。
- 认证密钥：bcrypt 哈希入配置、真实凭据只存 VPS 本地文件不入库（本仓库公开）。

## 参考

- [kafka-kraft-single-node-setup-research.md](./kafka-kraft-single-node-setup-research.md) — Kafka 4.4 KRaft 单节点全量调研（A 配置/内存/远程接入/安全，B 轻量替代，C 容器 vs 裸机）
- [nats-jetstream-single-node-setup-research.md](./nats-jetstream-single-node-setup-research.md) — NATS 2.15 JetStream 全量调研（A 版本/治理/安装，B 建模，C 安全/远程接入，D 运维，E 客户端矩阵+Python/Go 样例，F Kafka 对照与短板，G 可落地配置样例，H 最终推荐）
- 两份报告原生成于 `~/docs/`（research 技能产物），本条目归档时迁入；`~/docs/` 保留其他研究文档。
- reading-app 位置：`~/reading-app`（compose 部署）。

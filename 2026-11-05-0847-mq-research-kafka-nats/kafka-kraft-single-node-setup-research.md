# 单节点 Apache Kafka（KRaft）自托管调研报告

- **调研日期**：2026-11-05
- **目标机器**：搬瓦工 BandwagonHost VPS，Ubuntu 24.04.4 LTS x86_64，8 GB 内存 / 6 vCPU / 160 GB 磁盘（已用约 65 GB，内存已用约 1.5 GB）
- **用途**：为本地部署的应用（如 reading-app）投递领域事件（domain events）到 topic 并消费；未来可能有**其他 VPS 上的客户端远程连接**
- **调研方式**：全部关键事实仅采用一手来源（kafka.apache.org、cwiki.apache.org、apache/kafka GitHub、各项目官网/官方 GitHub/官方文档站），版本号均于 2026-11-05 当天到官网核实，未凭记忆填写
- **来源打不开的情况**：`kafka.apache.org/downloads` 已 301 重定向到 `https://kafka.apache.org/community/downloads/`（旧 URL 用 web-reader 抓到的还是旧缓存，改用 curl 抓真实页面才拿到 2026-10 的最新数据）；`apache/kafka-docker` 仓库不存在，官方镜像源码与示例在 `apache/kafka` 主仓库 `docker/` 目录；`docs.redpanda.com` 是 JS 渲染站点，改用其 `.md` 后缀直读 Markdown 源文件。其余来源均可正常访问。

---

## A. Apache Kafka KRaft 单节点

### A.1 当前最新版本与 3.x → 4.x 的关键变化

**最新稳定版：Apache Kafka 4.4.0，发布于 2026-10-22。** 当前官方"Supported releases"为 4.4.0 / 4.3.2（2026-10-23，含两个 tiered storage 数据丢失修复与多个 CVE 依赖升级）/ 4.2.2（2026-09-29）等，二进制包为 `kafka_2.13-4.4.0.tgz`（Scala 2.13 为推荐构建）。(来源: https://kafka.apache.org/community/downloads/)

官方下载页同时给出对应的官方 Docker 镜像标签：`apache/kafka:4.4.0`（JVM 版）与 `apache/kafka-native:4.4.0`（GraalVM 原生版）。(来源: https://kafka.apache.org/community/downloads/ 、https://kafka.apache.org/quickstart)

**3.x → 4.x 关键变化（均为官方文档确认）：**

| 变化 | 官方表述 | 来源 |
|---|---|---|
| ZooKeeper 彻底移除 | "Apache Kafka 4.0 only supports KRaft mode - ZooKeeper mode has been removed."（4.0.0 升级说明）；`zookeeper.connect` 等 ZooKeeper 配置全部移除 | https://kafka.apache.org/44/getting-started/upgrade/ 、https://kafka.apache.org/44/getting-started/zk2kraft/ |
| Java 最低版本 | "brokers, connect and tools now require Java 17. See KIP-750 and KIP-1013"；客户端/Streams 最低 Java 11。当前支持状态：Java 17/21/25 全面支持，Java 11 仅客户端与 Streams 子集，官方推荐最新 LTS（当前 Java 25） | https://kafka.apache.org/44/getting-started/upgrade/ 、https://kafka.apache.org/44/operations/java-version/ |
| KIP 编号更正 | 注意：**KIP-750 是"Drop support for Java 8 in Kafka 4.0"，KIP-1013 是"Drop broker and tools support for Java 11 in Kafka 4.0"**；"broker 要求 Java 17"是两者叠加的结果 | https://cwiki.apache.org/confluence/display/KAFKA/Kafka+Improvement+Proposals |
| `broker.id` 废弃 | deprecated，将在 Kafka 5.0 移除，改用 `node.id`（KIP-1232） | https://kafka.apache.org/44/configuration/broker-configs/ 、https://kafka.apache.org/44/getting-started/upgrade/ |
| 消费者组新协议 | KIP-848 新消费组协议在 4.0 GA | https://kafka.apache.org/44/getting-started/upgrade/ |
| 日志框架 | 4.0 起从 Log4j 迁移到 Log4j2（配置文件为 `log4j2.yaml`） | https://kafka.apache.org/44/getting-started/upgrade/ |

### A.2 KRaft 单节点（combined mode）标准配置步骤

**4.x 配置文件已统一（对任务描述中"KIP-858 part II"的更正）**：

- 任务描述里提到的 "KIP-858 part II" 编号有误。经查 cwiki 官方 KIP 索引，**KIP-858 实际是 "Handle JBOD broker disk failure in KRaft"**，与配置文件统一无关。(来源: https://cwiki.apache.org/confluence/spaces/KAFKA/pages/217392620/KIP-858+Handle+JBOD+broker+disk+failure+in+KRaft)
- 事实层面：对比 apache/kafka 仓库源码目录，3.9.0 的 KRaft 模板在 `config/kraft/` 子目录（另有 `zookeeper.properties`）；**4.0.0 起变为顶层三件套：`server.properties`（combined 模式模板，即官方 quickstart 用的那个）、`broker.properties`、`controller.properties`，`config/kraft/` 与 `zookeeper.properties` 消失**。(来源: https://github.com/apache/kafka/tree/3.9.0/config 、https://github.com/apache/kafka/tree/4.4.0/config)
- 官方 quickstart 直接用 `config/server.properties` 启动单节点，无需再拷贝 kraft 模板。(来源: https://kafka.apache.org/quickstart)

**标准三步（官方 quickstart 原文）**：

```bash
# 1. 生成 Cluster UUID
KAFKA_CLUSTER_ID="$(bin/kafka-storage.sh random-uuid)"

# 2. 格式化日志目录（4.x 单节点推荐 --standalone）
bin/kafka-storage.sh format --standalone -t $KAFKA_CLUSTER_ID -c config/server.properties

# 3. 启动
bin/kafka-server-start.sh config/server.properties
```
(来源: https://kafka.apache.org/quickstart)

**重要变化：`controller.quorum.voters` 已被动态仲裁（KIP-853）取代。** 任务描述中列的 `controller.quorum.voters` 是**旧的静态仲裁方式**。官方 KRaft 运维文档明确：

- "KRaft version 1 deprecated the `controller.quorum.voters` property and added the `controller.quorum.bootstrap.servers` property."（Kafka 4.1 起，KIP-853 动态控制器仲裁）
- broker-configs 里 `controller.quorum.voters` 的定义也写明："This is the old way of defining membership for controller quorums and should NOT be set if using dynamic quorums. Instead, `controller.quorum.bootstrap.servers` should be set, and the voter set is determined by the `--standalone` or `--initial-controllers` flags when formatting."
- 格式化时用了 `--standalone`/`--initial-controllers`/`--no-initial-controllers` 且未设置 `controller.quorum.voters`，即自动成为动态仲裁。

(来源: https://kafka.apache.org/44/operations/kraft/ 、https://kafka.apache.org/44/configuration/broker-configs/ 、KIP-853: https://cwiki.apache.org/confluence/spaces/KAFKA/pages/217391519/KIP-853+KRaft+Controller+Membership+Changes)

**4.4.0 官方 `config/server.properties` 模板原文关键行**（来源: https://raw.githubusercontent.com/apache/kafka/4.4.0/config/server.properties）：

```properties
process.roles=broker,controller
node.id=1
controller.quorum.bootstrap.servers=localhost:9093
listeners=PLAINTEXT://:9092,CONTROLLER://:9093
inter.broker.listener.name=PLAINTEXT
advertised.listeners=PLAINTEXT://localhost:9092,CONTROLLER://localhost:9093
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_SSL:SASL_SSL
log.dirs=/tmp/kraft-combined-logs
num.partitions=1
# 单节点必须把内部 topic 副本因子降为 1（模板已给出）
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
```

**combined mode 的官方定位**："Combined servers are simpler to operate for small use cases like a development environment... Combined mode is not recommended in critical deployment environments."（对个人自托管场景完全适用；Confluent 文档同样表述 combined "not supported for production environments"）。(来源: https://kafka.apache.org/44/operations/kraft/ 、https://docs.confluent.io/platform/current/installation/installing_cp/deb-ubuntu.html)

### A.3 内存占用与 JVM 调优

**官方事实：**

- 官方启动脚本默认堆：`KAFKA_HEAP_OPTS="-Xmx1G -Xms1G"`（4.4.0 的 `bin/kafka-server-start.sh` 原文）。(来源: https://raw.githubusercontent.com/apache/kafka/4.4.0/bin/kafka-server-start.sh)
- 官方 Java 版本页给出的"典型生产 JVM 参数"（参考 LinkedIn 最繁忙集群，60 broker、5 万分区、80 万 msg/s）：`-Xmx6g -Xms6g -XX:MetaspaceSize=96m -XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35 -XX:G1HeapRegionSize=16M -XX:MinMetaspaceFreeRatio=50 -XX:MaxMetaspaceFreeRatio=80 -XX:+ExplicitGCInvokesConcurrent` —— 这是**超大集群**的参照，不是单节点需求。(来源: https://kafka.apache.org/44/operations/java-version/)
- 官方硬件页：Kafka 依赖 **OS page cache** 做读写缓冲，堆内存只需要缓冲活跃读写："memory need ≈ write_throughput × 30 秒"；参考机型为 24 GB 内存的四核机器。(来源: https://kafka.apache.org/44/operations/hardware-and-os/)
- OS 层建议：broker 进程文件描述符 ≥ 100000；关注 `vm.max_map_count`（默认约 65535，每个 log segment 占 2 个 map area，分区极多时会 OOM）。(来源: https://kafka.apache.org/44/operations/hardware-and-os/)

**针对本机（8 GB，领域事件低吞吐场景）的建议堆配置**（基于上述官方数字推导）：

```bash
export KAFKA_HEAP_OPTS="-Xmx768m -Xms768m -XX:+UseG1GC -XX:MaxGCPauseMillis=20"
```

单节点、几十个分区、低 QPS 的领域事件负载，768 MB～1 GB 堆绰绰有余（官方默认就是 1G）；剩余内存留给 OS page cache（Kafka 官方设计就依赖 page cache 而非大堆）和机器上的其他服务。整个 Kafka 进程 RSS 预计 1.5 GB 以内。

### A.4 远程连接的关键配置（advertised.listeners）

**官方定义**（broker-configs）：

> `advertised.listeners`: "Specifies the listener addresses that the Kafka brokers will advertise to clients... Unlike `listeners`, it is not valid to advertise the 0.0.0.0 meta-address."

(来源: https://kafka.apache.org/44/configuration/broker-configs/)

**机制与常见坑**：客户端先连 `bootstrap.servers` 拿到元数据，然后**按 broker 返回的 `advertised.listeners` 地址直连各 broker**。所以：

1. 对外 listener 的 advertised 地址必须是**客户端可路由的外网 IP 或域名**，不能是 `0.0.0.0`（非法）、不能是内网 IP（客户端拿到后连不上，典型症状是 producer 报 `Connection refused`/超时，metadata 拿到了但数据发不出去）。
2. 本地 listener 与外部 listener 用**不同端口**，各自 advertise 各自的地址；`listeners` 决定绑哪里（可用 `0.0.0.0` 或指定内网/隧道 IP），`advertised.listeners` 决定广播什么。
3. `listener.security.protocol.map` 给每个自定义 listener 名映射安全协议，可选值 `PLAINTEXT / SSL / SASL_PLAINTEXT / SASL_SSL`（官方建议给 listener 起显式名字而不是直接用协议名）。(来源: https://kafka.apache.org/44/security/listener-configuration/)

**双 listener 模板（本地 PLAINTEXT + 外部 EXTERNAL）**——官方镜像示例 `PLAINTEXT_HOST://localhost:9092,PLAINTEXT://broker:19092` 即这个模式（来源: https://github.com/apache/kafka/blob/trunk/docker/examples/docker-compose-files/single-node/plaintext/docker-compose.yml），落到裸机 server.properties：

```properties
# 绑定：本地 127.0.0.1、外部 0.0.0.0（或公网网卡 IP）、控制器仅 localhost
listeners=INTERNAL://127.0.0.1:9092,EXTERNAL://0.0.0.0:9094,CONTROLLER://127.0.0.1:9093
advertised.listeners=INTERNAL://127.0.0.1:9092,EXTERNAL://your.public.domain.example:9094
listener.security.protocol.map=INTERNAL:PLAINTEXT,EXTERNAL:SASL_SSL,CONTROLLER:PLAINTEXT
inter.broker.listener.name=INTERNAL
controller.listener.names=CONTROLLER
```

（未配置 `advertised.listeners` 时取 `listeners` 的值；CONTROLLER listener 不对客户端广播。来源: https://kafka.apache.org/44/configuration/broker-configs/ 、https://kafka.apache.org/44/security/listener-configuration/）

### A.5 安全：把 Kafka 暴露到公网的正确姿势

**为什么绝不能用无认证 PLAINTEXT 暴露公网**：官方对 PLAINTEXT 的描述是 "The plaintext protocol provides no security and does not require any additional configuration"——无加密、无认证，公网上等于**任何人都可以读写/删除 topic、创建任意 topic、拉走全部领域事件数据**；Kafka 协议是公开的二进制协议，扫描器可以直接打。官方安全文档的所有监听器方案都以 PLAINTEXT 仅限可信网络为前提。(来源: https://kafka.apache.org/44/security/listener-configuration/)

**方案一：SASL_SSL + SCRAM-SHA-512（推荐，配置要点均出自官方文档）**

Kafka 支持 SASL 机制：GSSAPI / PLAIN / SCRAM-SHA-256 / SCRAM-SHA-512 / OAUTHBEARER；"SCRAM-SHA-256 and SCRAM-SHA-512 ... can be used with TLS to perform secure authentication"。(来源: https://kafka.apache.org/44/security/authentication-using-sasl/)

KRaft 模式下 SCRAM 凭据存在**元数据日志**里（不再依赖 ZooKeeper）：

```bash
# 格式化时注入初始 SCRAM 凭据（官方原文用法）
bin/kafka-storage.sh format -t $(bin/kafka-storage.sh random-uuid) \
    -c config/server.properties \
    --add-scram 'SCRAM-SHA-512=[name="admin",password="***"]'

# 运行期增改用户凭据（官方原文用法，iterations 缺省 4096）
bin/kafka-configs.sh --bootstrap-server localhost:9092 --alter \
    --add-config 'SCRAM-SHA-512=[iterations=8192,password="***"]' \
    --entity-type users --entity-name app-reader
```
(来源: https://kafka.apache.org/44/security/authentication-using-sasl/)

broker 端（SCRAM 可与 SASL_PLAINTEXT 或 SASL_SSL 搭配；**公网必须用 SASL_SSL**）：

```properties
listeners=INTERNAL://127.0.0.1:9092,EXTERNAL://0.0.0.0:9094,CONTROLLER://127.0.0.1:9093
advertised.listeners=INTERNAL://127.0.0.1:9092,EXTERNAL://kafka.example.com:9094
listener.security.protocol.map=INTERNAL:PLAINTEXT,EXTERNAL:SASL_SSL,CONTROLLER:PLAINTEXT
inter.broker.listener.name=INTERNAL
controller.listener.names=CONTROLLER
sasl.enabled.mechanisms=SCRAM-SHA-512
listener.name.external.sasl.enabled.mechanisms=SCRAM-SHA-512
# TLS（证书可用 Let's Encrypt，PEM/JKS 均可）
listener.name.external.ssl.keystore.location=/etc/kafka/secrets/server.keystore.jks
listener.name.external.ssl.keystore.password=***
listener.name.external.ssl.key.password=***
listener.name.external.ssl.truststore.location=/etc/kafka/secrets/server.truststore.jks
listener.name.external.ssl.truststore.password=***
# 每个listener/机制单独的 JAAS（也可用静态 JAAS 文件 + KAFKA_OPTS 传入）
listener.name.external.scram-sha-512.sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="admin" password="***";
```

官方 SSL 配置项原文即 `ssl.keystore.location / ssl.keystore.password / ssl.key.password / ssl.truststore.location / ssl.truststore.password`（truststore 密码"technically optional but highly recommended"）。(来源: https://kafka.apache.org/44/security/encryption-and-authentication-using-ssl/ 、https://kafka.apache.org/44/security/authentication-using-sasl/)

**mTLS 变体**：设 `ssl.client.auth=requested/required` 后客户端必须出示证书，broker truststore 需包含签发客户端证书的 CA："If you configure the Kafka brokers to require client authentication by setting `ssl.client.auth` to be 'requested' or 'required'..."。个人自托管用 SASL_SSL+SCRAM 运维更简单（加减用户不用发证书）。(来源: https://kafka.apache.org/44/security/encryption-and-authentication-using-ssl/)

**方案二：WireGuard / Tailscale 私网**：

- 官方文档**没有**专门推荐 VPN 方案（这属于网络层实践，不在 Kafka 文档范围内），但官方机制完全支持：`listeners` 可绑定到指定网卡/IP（"Specify hostname as 0.0.0.0 to bind to all interfaces. Leave hostname empty to bind to default interface"），把 EXTERNAL listener 绑到 WireGuard 接口 IP（如 `10.x.x.x`）并 advertised 该 IP，即可实现"Kafka 只在隧道内可达"。(来源: https://kafka.apache.org/44/configuration/broker-configs/ 中 `listeners` 条目)
- 该方案的实质收益：Kafka 保持简单 PLAINTEXT listener，认证/加密交给内核态 WireGuard（或 Tailscale 的加密 overlay + ACL），无需证书轮换、无需 SCRAM 用户管理；代价是每台客户端 VPS 都要入网。
- Redpanda 官方 quickstart 的双地址模式（`--kafka-addr internal://...,external://...` + `--advertise-kafka-addr`）同样体现"内外双 listener"是这类自托管的通用形态。(来源: https://docs.redpanda.com/streaming/current/get-started/quick-start/)

### A.6 systemd 服务单元最佳实践

- Apache Kafka 官方发行包（tar.gz）**不附带** systemd unit，官方 quickstart 只用前台脚本。上游发行版的官方参照是 Confluent 的 deb/rpm 安装：`sudo systemctl start confluent-server`（社区包为 `confluent-kafka`），其文档 "Install Confluent Platform using Systemd on Ubuntu and Debian" 给出 systemctl enable/start 与 unit 文件说明。(来源: https://docs.confluent.io/platform/current/installation/installing_cp/deb-ubuntu.html 、https://docs.confluent.io/platform/current/installation/scripted-install.html#installing-systemd-unit)
- 依据官方脚本语义（`kafka-server-stop.sh` 做优雅关停）与 Confluent 的 systemd 实践，裸机部署可用如下 unit（`/etc/systemd/system/kafka.service`）：

```ini
[Unit]
Description=Apache Kafka (KRaft combined mode)
Documentation=https://kafka.apache.org/quickstart
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=kafka
Group=kafka
Environment=KAFKA_HEAP_OPTS=-Xmx768m -Xms768m -XX:+UseG1GC
Environment=KAFKA_JVM_PERFORMANCE_OPTS=-XX:MetaspaceSize=96m
Environment="JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64"
ExecStart=/opt/kafka/bin/kafka-server-start.sh -daemon /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
LimitNOFILE=100000
Restart=on-failure
RestartSec=10
TimeoutStopSec=60
# 加固（可选）
NoNewPrivileges=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
```

要点：`-daemon` 为官方脚本支持的守护参数（`USAGE: kafka-server-start.sh [-daemon] server.properties [--override property=value]*`，来源: https://github.com/apache/kafka/blob/4.4.0/bin/kafka-server-start.sh）+ `Type=forking`；`LimitNOFILE=100000` 直接采用官方硬件页的底线数字（来源: https://kafka.apache.org/44/operations/hardware-and-os/）；优雅停止用官方 `kafka-server-stop.sh`（SIGTERM+等待，避免元数据日志损坏）。

### A.7 运维要点：磁盘控制与常用 CLI

**保留策略（默认值出自 4.4.0 官方模板与 broker-configs）**：

| 配置 | 默认值 | 说明 |
|---|---|---|
| `log.retention.hours` | 168（7 天） | 按 time 删旧 segment；`log.retention.ms`/`.minutes` 优先级更高，-1 为无限 |
| `log.retention.bytes` | -1（不限制） | 按 size 删旧 segment；与时间策略**相互独立、任一满足即删** |
| `log.segment.bytes` | 1073741824（1 GiB） | 单个 log segment 大小，写满滚动 |
| `log.retention.check.interval.ms` | 300000 | 删除检查周期 |

(来源: https://kafka.apache.org/44/configuration/broker-configs/ 、https://github.com/apache/kafka/blob/4.4.0/config/server.properties)

针对本机（剩余约 95 GB，还要留给其他服务）：建议给 Kafka 数据单独目录并设 `log.retention.bytes`（如每 topic 默认 2–5 GB 级别的全局上限）+ `log.retention.hours=72` 双保险；topic 级可随时用 `kafka-configs.sh --alter --add-config retention.ms=...` 覆盖。

**常用 CLI（官方 quickstart / basic operations 原文）**：

```bash
bin/kafka-topics.sh --create --topic quickstart-events --bootstrap-server localhost:9092
bin/kafka-topics.sh --describe --topic quickstart-events --bootstrap-server localhost:9092
bin/kafka-topics.sh --create --topic my_topic --bootstrap-server localhost:9092 \
    --partitions 3 --replication-factor 1 --config retention.ms=259200000
bin/kafka-console-producer.sh --topic quickstart-events --bootstrap-server localhost:9092
bin/kafka-console-consumer.sh --topic quickstart-events --from-beginning --bootstrap-server localhost:9092
```
(来源: https://kafka.apache.org/quickstart 、https://kafka.apache.org/44/operations/basic-kafka-operations/)

---

## B. 更轻量的开源替代方案

### B.1 Redpanda

- **Kafka API 兼容 / 无 JVM**：官方仓库自述 "Redpanda is a streaming data platform for developers. Kafka API compatible. 10x faster. No ZooKeeper. No JVM!"，C++ 单二进制。(来源: https://github.com/redpanda-data/redpanda)
- **当前版本**：v26.2 系列（按年份命名）。文档站标注最新 tag **v26.2.6**，v26.2 于 2026-07 发布、支持至 2027-07-28；GitHub 最新正式 release 为 v26.2.2（2026-08-22）。(来源: https://docs.redpanda.com/streaming/current/deploy/redpanda/manual/production/requirements.md 页面元数据 、https://github.com/redpanda-data/redpanda/releases)
- **许可证（重点核实）**：核心代码为 **BSL 1.1**（源码可用、非 OSI），带 Additional Use Grant："You may make use of the Licensed Work, provided that you may not use the Licensed Work for a Streaming or Queuing Service"（即**只要不把 Redpanda 当作服务卖给第三方，自托管使用免费且允许**，自己的应用发事件完全合规）；Change Date 为发布后 4 年，届时自动转 **Apache 2.0**。企业功能走 **RCL（Redpanda Community License）**，需付费。(来源: https://github.com/redpanda-data/redpanda/blob/dev/licenses/bsl.md 、https://github.com/redpanda-data/redpanda/blob/dev/licenses/README.md 、https://github.com/redpanda-data/redpanda/blob/dev/licenses/rcl.md)
- **社区版 vs 企业版**：Community Edition 免费含核心 Kafka API 功能；Enterprise Edition（RCL）功能要付费订阅。(来源: 同上 RCL 第 2(a)/4 节)
- **单节点资源要求（官方生产要求页）**：每节点 ≥2 个物理核；**每核 ≥2 GB 内存**（即单节点最低约 4 GB 级别）、每分区副本 ≥2 MB 内存；Ubuntu 20.04 起（推荐 22.04+）；x86_64（Westmere+）与 Arm。官方 quickstart 的 3-broker compose 要求"至少 4 GB 空闲内存"。**在这台 8 GB 且与其他服务共存的 VPS 上，Redpanda 会比 Kafka 占用更多内存，这是关键结论。**(来源: https://docs.redpanda.com/streaming/current/deploy/redpanda/manual/production/requirements.md 、https://docs.redpanda.com/streaming/current/get-started/quick-start/)
- **官方 Docker 镜像**：`docker.redpanda.com/redpandadata/redpanda:v26.2.6`（quickstart compose 原文；Docker Hub 同名 `redpandadata/redpanda`）。(来源: https://docs.redpanda.com/streaming/current/get-started/quick-start/)

### B.2 NATS + JetStream

- **许可证/形态**：**Apache 2.0**，Go 编写，"single binary with no external dependencies"；官方明确 "The server typically uses less than **20MB** of RAM"。CNCF 孵化项目。(来源: https://github.com/nats-io/nats-server （GitHub API license=Apache-2.0）、https://nats.io/about/)
- **当前版本**：nats-server **v2.15.2**（2026-10-26）。(来源: https://github.com/nats-io/nats-server/releases/latest)
- **JetStream 模型与领域事件匹配度**：官方概念文档——**Stream** 是服务端消息存储（绑定 subject，`--storage file` 即单文件磁盘持久化，支持 limits/interest/workqueue 保留策略）；**Consumer** 是服务端有状态游标，durable pull consumer + ack + 超时重投 = **at-least-once**；"A consumer can be shared by multiple clients to divide the work" —— 这正是 Kafka 消费组语义的对应物。消费可从头/指定 offset/时间点开始，天然支持回放。(来源: https://docs.nats.io/nats-concepts/jetstream 、https://nats.io/about/)
- 结论：模型上完全覆盖"领域事件投递 + 消费组 + 持久化 + 回放"需求，且是所有候选中内存占用最小（几十 MB 级）、运维最简单的。

### B.3 RabbitMQ

- **许可证/版本**：核心服务器 **MPL 2.0**（仓库 LICENSE 原文："RabbitMQ server and its tier 1 (core) plugins source code is licensed under the MPL 2.0."），Erlang 运行时。当前最新 **v4.4.0**（2026-10-19）。(来源: https://github.com/rabbitmq/rabbitmq-server/blob/main/LICENSE 、https://github.com/rabbitmq/rabbitmq-server/releases/latest)
- **内存模型**：默认内存水位线 `vm_memory_high_watermark.relative = 0.6`（可用 RAM 的 60%）——注意它是**触发 publisher 阻塞的阈值而非硬上限**；容器环境官方建议改用绝对值 `vm_memory_high_watermark.absolute`。(来源: https://www.rabbitmq.com/docs/memory)
- **"ack 即删"的澄清（重要）**：官方文档确认**经典/仲裁队列是 destructive consume**（"messages are deleted from the queue when a consumer is finished with them ... not possible to re-read messages that have been consumed"）；但 RabbitMQ 3.9+ 提供 **Streams**（append-only log、可反复读、非破坏性消费语义、`max-age`/`max-length-bytes` 保留策略、super streams 分区、single active consumer 保序）。也就是说 RabbitMQ 也能做事件回放，但要用 Streams 而非普通队列，且 Streams 偏磁盘 I/O 型。对"已有领域事件流 + 多消费者独立回放"的 Kafka 式用法，RabbitMQ Streams 能做但生态/API 形态更绕。(来源: https://www.rabbitmq.com/docs/streams)
- 内存占用：Erlang VM 空载约 100–150 MB 级别（具体取决于队列与消息量；官方文档不承诺固定数字，可用水位线绝对值约束）。

### B.4 Redis Streams / Valkey

- **许可证变更史（官方 legal 页面原文核实）**：Redis ≤7.2 为 BSD-3-Clause；7.4–7.8 为 RSALv2 / SSPLv1 双许可（2024-03 变更）；**≥8.0 起为三重许可 RSALv2 / SSPLv1 / AGPLv3**（2025 年随 Redis 8 加入 AGPLv3，"This is not a license change, but rather the inclusion of an option"）。AGPLv3 是 OSI 认证的开源许可证，普通自托管使用无影响；但若对许可证敏感（如不想引入 AGPL 网络条款），Valkey 是 BSD 分叉。(来源: https://redis.io/legal/licenses/)
- **Valkey**：Linux Foundation 主导的 Redis 7.2 分叉，**BSD-3-Clause**，当前最新 **9.1.3**（2026-10-26）。(来源: https://github.com/valkey-io/valkey （GitHub API license=BSD-3-Clause）、https://github.com/valkey-io/valkey/releases/latest)
- **能力边界**：Valkey/Redis 都有 `XADD` Streams + `XGROUP` consumer group（Valkey 继承自 Redis 7.2 代码库），适合"事件投递 + 消费组"；但保留策略（`MAXLEN`/`MINID`、`XTRIM`）基于**条数/ID，存储在内存**（AOF/RDB 持久化是全量快照/追加日志，不是"按时间保留的磁盘日志"），**没有 Kafka 式按时间/字节的磁盘保留策略与分段日志**；长回放历史会持续吃内存。适合"已有 Redis/Valkey 且只需要短窗口事件流"的场景，不适合当长期事件存储。

### B.5 Apache Pulsar（为什么单节点反而更重）

- 官方架构文档：一个 Pulsar 集群 = **broker（无状态）+ BookKeeper 集群（bookie，持久化存储）+ 元数据存储集群（Oxia 或 ZooKeeper）** 三种角色；"A BookKeeper cluster consisting of one or more bookies handles persistent storage of messages. A metadata store cluster (Oxia, ZooKeeper, or other supported backend) handles coordination tasks"。即使单机部署也要同时拉起 3 类进程，内存/运维开销对单节点场景明显高于 KRaft（Kafka 把这三层合并成了一个进程）。(来源: https://pulsar.apache.org/docs/5.0.x/concepts-architecture-overview/ ；最新版 v5.0.1，https://github.com/apache/pulsar/releases/latest)

### B.6 对比总结：Kafka vs Redpanda vs NATS（针对"个人自托管 + 领域事件 + 持久化 + 消费组 + 8 GB 与其他服务共存"）

| 维度 | Apache Kafka 4.4 (KRaft) | Redpanda 26.2 | NATS 2.15 + JetStream |
|---|---|---|---|
| 许可证 | Apache 2.0 | BSL 1.1（非服务转售即免费；4 年后转 Apache 2.0）+ RCL 付费企业功能 | Apache 2.0 |
| 形态 | JVM，tar 包 + 脚本 | C++ 单二进制，无 JVM | Go 单二进制 |
| 单节点内存（官方口径） | 默认堆 1G（可降到 768M），总 RSS ≈1.5 GB；堆外靠 page cache | 生产要求每核 ≥2 GB（单节点 4 GB 级）+ 每分区 2 MB | 典型 <20 MB |
| 领域事件 + 消费组 + 回放 | 原生（topic/consumer group/retention） | 原生（Kafka API 兼容） | 原生（stream/durable consumer/ack） |
| 客户端生态 | 最广（各语言 + 生态工具） | 复用 Kafka 客户端 | 官方客户端 10+ 语言，够用但生态小 |
| 在这台 8GB VPS 上 | 跑得动，留 6 GB+ 给别的 | 内存要求最高，与"共存"目标冲突 | 最轻，几乎无感 |

**取舍建议**：如果坚持 Kafka API 生态（现有代码用 kafka 客户端、未来可能接 Connect/Streams），用 **Apache Kafka KRaft 单节点**而不是 Redpanda（Redpanda 的官方生产内存要求反而更高，与"和 reading-app 等共存于 8G 机器"矛盾）；如果事件量小、想要"零负担常驻"，**NATS JetStream** 是最省资源的正解；RabbitMQ 适合路由/任务队列形态，做事件回放要绕道 Streams；Redis/Valkey Streams 只在"已有实例、短窗口"时考虑。

---

## C. Docker/Podman 部署 vs 裸机部署

### C.1 apache/kafka 官方镜像现状

- 官方 JVM 镜像 `apache/kafka` 自 **3.7.0** 起在 Docker Hub 提供，KRaft 是默认形态：`docker run -p 9092:9092 apache/kafka:4.4.0` 无任何环境变量即可起单节点（容器内置默认 cluster id 与默认配置）。(来源: https://kafka.apache.org/44/getting-started/docker/ 、https://kafka.apache.org/quickstart)
- GraalVM 原生镜像 `apache/kafka-native` 自 3.8.0 起提供，官方明确标注 **experimental，不推荐生产**；4.4.0 起原生镜像才支持 SASL。(来源: https://kafka.apache.org/44/getting-started/docker/)
- 配置方式：全部走 `KAFKA_*` 环境变量（映射为 server.properties 键）或挂载配置文件；环境变量优先级高于文件。官方单节点示例（原文摘录）：

```yaml
services:
  broker:
    image: apache/kafka:4.4.0
    ports: ['9092:9092']
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: 'broker,controller'
      KAFKA_CONTROLLER_QUORUM_VOTERS: '1@broker:29093'   # 镜像示例仍用静态 voters（兼容旧法）
      KAFKA_LISTENERS: 'CONTROLLER://:29093,PLAINTEXT_HOST://:9092,PLAINTEXT://:19092'
      KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT_HOST://localhost:9092,PLAINTEXT://broker:19092'
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: 'CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT'
      KAFKA_INTER_BROKER_LISTENER_NAME: 'PLAINTEXT'
      KAFKA_CONTROLLER_LISTENER_NAMES: 'CONTROLLER'
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_LOG_DIRS: '/tmp/kraft-combined-logs'
```
(来源: https://github.com/apache/kafka/blob/trunk/docker/examples/README.md 、https://github.com/apache/kafka/blob/trunk/docker/examples/docker-compose-files/single-node/plaintext/docker-compose.yml)

### C.2 bitnami/kafka 2025 年后的变化（已核实）

- bitnami/containers 官方 README：Bitnami 镜像已转为 **Bitnami Secure Images，基底从 Debian 换成 Photon Linux**，完整安全特性（VEX/合规/attestation）需商业订阅；"If you are looking for our previous generation of images based on Debian Linux, please see the **Bitnami Legacy registry**（hub.docker.com/u/bitnamilegacy）"；废弃镜像会移到 `bitnami/<app>-archived`。(来源: https://github.com/bitnami/containers/blob/main/README.md)
- Docker Hub 数据印证：`bitnami/kafka` 描述已改为 "Bitnami Secure Image for kafka"，**last_updated 停在 2025-08-29**——原 Debian 版免费目录事实上冻结，旧镜像迁移至 `bitnamilegacy/kafka`，新镜像策略向付费 BSI 收敛。**个人自托管不应再默认选 bitnami/kafka**（更新不确定 + 政策变动风险）。(来源: https://hub.docker.com/v2/repositories/bitnami/kafka/ 、https://github.com/bitnami/containers/blob/main/bitnami/kafka/README.md)

### C.3 容器 vs 裸机（本机有 podman）

| | 容器（podman + apache/kafka） | 裸机（JDK + systemd） |
|---|---|---|
| 优点 | 一条命令起；版本升级/回滚干净（镜像 tag）；配置全在 env/compose，可纳入现有 compose 栈管理；不污染主机 Java 环境 | 少一层抽象，内存/IO 开销最小；JVM 参数、日志、jstack/jcmd 等诊断直接可用；官方脚本 + systemd 生命周期最直白 |
| 缺点 | 需注意数据卷持久化（`KAFKA_LOG_DIRS` 要挂 volume，容器重建需重用 CLUSTER_ID，格式化目录不能丢）；主机侧 CLI 要另跑或进容器；网络多一层（端口映射/双 listener 地址要写对） | 要自己装 JDK 17/21/25、建用户、写 unit、管理升级（换目录+systemd restart） |

对本机推荐：**两者都可行**。若 reading-app 等已用 compose 管理，用 `apache/kafka`（官方镜像，quay/docker hub 均可拉）挂 volume 部署最省心；若追求最小开销与最直观的 systemd 运维，裸机 JDK 21 + 上文 unit。bitnami/kafka 不推荐。

---

## 针对这台机器的推荐方案（总结）

**1. Kafka 跑得动吗？——明确结论：跑得动，且余量充足。**
Apache Kafka 4.4.0 KRaft combined 单节点默认堆仅 1 GB（官方脚本默认值），在本机建议压到 768 MB 堆 + G1GC，配合 OS page cache，整个 broker 常驻 RSS 约 1.2–1.5 GB；机器 8 GB、当前仅用 1.5 GB，Kafka 之外仍留有 5 GB 以上给 reading-app 及其他服务。磁盘剩约 95 GB，设 `log.retention.bytes` + `log.retention.hours=72` 足以兜底。前提：安装 JDK 17+（官方推荐最新 LTS，Java 21/25 皆可）。

**2. 推荐参数（可直接落地）**
- 版本：`kafka_2.13-4.4.0.tgz`；JDK 21 或 25（apt 的 openjdk-21-jdk-headless 即可）。
- server.properties：以 4.4.0 官方模板为基（见 A.2），叠加：双 listener（INTERNAL 127.0.0.1:9092 PLAINTEXT / EXTERNAL :9094 SASL_SSL，advertise 公网域名）、`controller.quorum.bootstrap.servers=localhost:9093`（不要再用 `controller.quorum.voters`）、CONTROLLER listener 只绑 localhost、内部 topic 副本因子全部 =1、`log.dirs=/var/lib/kafka/data`（独立目录）、`auto.create.topics.enable=false`（显式建 topic，避免误建）。
- 格式化：`kafka-storage.sh format --standalone --add-scram 'SCRAM-SHA-512=[name="admin",password=...]'`（一步注入 SCRAM 凭据）。
- JVM：`KAFKA_HEAP_OPTS="-Xmx768m -Xms768m -XX:+UseG1GC -XX:MaxGCPauseMillis=20"`。
- systemd：见 A.6 unit（LimitNOFILE=100000，ExecStop 用官方 stop 脚本）。

**3. 远程接入：公网 SASL_SSL vs WireGuard/Tailscale**
- **只有一台外部客户端、想零证书运维** → WireGuard/Tailscale：EXTERNAL listener 绑隧道 IP 并 advertise 隧道 IP，公网完全不暴露 9092/9094 端口；官方 `listeners` 支持绑定指定接口，此法在 Kafka 文档覆盖范围外但机制官方支持（诚实说明：官方文档不背书 VPN 方案）。
- **不想维护 VPN、或多台外部机器要接** → 公网 SASL_SSL + SCRAM-SHA-512 + Let's Encrypt 证书：这是官方文档完整覆盖的路径（A.5 配置可直接抄）。**任何情况下都不要把 PLAINTEXT listener 暴露公网。**

**4. 什么时候改用 NATS / Redpanda**
- 想把常驻内存从 ~1.5 GB 降到 ~50 MB、且不需要 Kafka 客户端生态 → **NATS JetStream**（Apache 2.0，单二进制，stream+durable consumer 完整覆盖领域事件+消费组语义）。
- 不会在这台 8 GB 机器上选 Redpanda：其官方生产内存要求（每核 ≥2 GB）比 Kafka 单节点更高，与"与其他服务共存"的目标相反；只有在内存充裕、追求单二进制无 JVM 且必须 Kafka API 时才值得。
- 已有 Valkey/Redis 且事件只需短窗口 → `XADD`/`XGROUP` 可顶一阵，但注意保留策略基于内存条数、无按时间的磁盘保留，别当长期事件存储。

---

## 附：本报告引用的一手来源清单

| 主题 | URL |
|---|---|
| Kafka 下载/版本 | https://kafka.apache.org/community/downloads/ |
| Kafka quickstart | https://kafka.apache.org/quickstart |
| Kafka 4.4 升级说明（ZK 移除/Java 17） | https://kafka.apache.org/44/getting-started/upgrade/ |
| Java 版本与官方 JVM 参数 | https://kafka.apache.org/44/operations/java-version/ |
| 硬件与 OS（page cache/fd/max_map_count） | https://kafka.apache.org/44/operations/hardware-and-os/ |
| KRaft 运维（KIP-853 动态仲裁/format --standalone） | https://kafka.apache.org/44/operations/kraft/ |
| Broker 配置参考 | https://kafka.apache.org/44/configuration/broker-configs/ |
| 4.4.0 官方 server.properties 模板 | https://github.com/apache/kafka/blob/4.4.0/config/server.properties |
| 启动脚本默认堆 | https://github.com/apache/kafka/blob/4.4.0/bin/kafka-server-start.sh |
| Listener/安全 | https://kafka.apache.org/44/security/listener-configuration/ |
| SASL/SCRAM | https://kafka.apache.org/44/security/authentication-using-sasl/ |
| SSL/mTLS | https://kafka.apache.org/44/security/encryption-and-authentication-using-ssl/ |
| Kafka Docker | https://kafka.apache.org/44/getting-started/docker/ 及 https://github.com/apache/kafka/blob/trunk/docker/examples/README.md |
| KIP 索引（KIP-750/833/858/853/1013） | https://cwiki.apache.org/confluence/display/KAFKA/Kafka+Improvement+Proposals |
| Confluent systemd 安装 | https://docs.confluent.io/platform/current/installation/installing_cp/deb-ubuntu.html |
| Redpanda 许可证 | https://github.com/redpanda-data/redpanda/blob/dev/licenses/bsl.md （及 licenses/README.md、licenses/rcl.md） |
| Redpanda 生产要求 | https://docs.redpanda.com/streaming/current/deploy/redpanda/manual/production/requirements.md |
| Redpanda quickstart/内存/Docker 镜像 | https://docs.redpanda.com/streaming/current/get-started/quick-start/ |
| NATS 官网（20MB/Apache2.0） | https://nats.io/about/ |
| NATS JetStream 概念 | https://docs.nats.io/nats-concepts/jetstream |
| RabbitMQ 许可证 | https://github.com/rabbitmq/rabbitmq-server/blob/main/LICENSE |
| RabbitMQ 内存水位线 | https://www.rabbitmq.com/docs/memory |
| RabbitMQ Streams | https://www.rabbitmq.com/docs/streams |
| Redis 许可证变迁 | https://redis.io/legal/licenses/ |
| Valkey 仓库（BSD-3） | https://github.com/valkey-io/valkey |
| Pulsar 架构（broker+BookKeeper+metadata） | https://pulsar.apache.org/docs/5.0.x/concepts-architecture-overview/ |
| Bitnami 目录变动 | https://github.com/bitnami/containers/blob/main/README.md 、https://github.com/bitnami/containers/blob/main/bitnami/kafka/README.md 、https://hub.docker.com/v2/repositories/bitnami/kafka/ |

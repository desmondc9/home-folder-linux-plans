# 免费云托管 Redis/Valkey 调研（"Supabase/Neon of Redis"）

- 环境: brave-goose-1 VPS（7.3G 内存）；此前自建 shared-redis（`~/redis-deploy`，256MB maxmemory，ADR-0003）已于 2026-09-22 随 LibreChat 停栈下线（ADR-0010），配置目录与 `.env` 保留，一条命令可重建。
- 日期: 2026-11-14
- 状态: 调研完成（额度数字全部当日从一手来源核实）；未注册未部署。
- 关联: 与 [2026-11-14-1556-rakazo-supabase-migration-research](../2026-11-14-1556-rakazo-supabase-migration-research/)（免费层 Postgres 卸载 VPS 负载）同一主线；填补"此前从未调研过免费 Redis"的空白（`~/plans` 129 项 + opencode 会话库均无此题记录）。

## 背景与目标

用户问："有没有免费的云托管 Redis，类似 Supabase/Neon 版的免费 PostgreSQL"。即：**永久免费（非试用）、托管、协议兼容 redis-cli、hobby 项目够用**。潜在动机是给 7.3G 内存的 VPS 减负（旧 shared-redis 限 384MB/mem_limit）。

## 范围

- In：主流托管 Redis/Valkey 免费层——额度/连接数/吞吐/带宽/持久化/空闲策略/区域选择/信用卡要求，一手来源（官方定价页、官方文档）当日核实，关键数字第三方交叉核对（标注日期）。
- Out：实际注册部署（后续任务）、付费层细化对比、自托管方案（`~/redis-deploy` 随时可拉起）、中国大陆厂商（免费均为限时试用，不符合"永久免费"标准）。

## 关键结论

一句话：**Redis 界的 Supabase/Neon = Upstash**（按量计费 + 永久免费层，全托管体验最像）；**资源最大的免费层 = Aiven Valkey Free**（1C/1G 专用 VM，~512MB 可用）；**官方 Redis 的小号免费 = Redis Cloud 30MB**（限制太窄，只适合学习/兼容性验证）。注意：**Supabase/Neon 本身不提供 Redis**（只有 Postgres）。

### 永久免费层对比（2026-11-14 核实）

| 维度 | Upstash Free | Aiven Valkey Free | Redis Cloud Free (Essentials) | Render Key Value Free |
|---|---|---|---|---|
| 引擎 | Redis 兼容 | Valkey（Redis 7.2 分叉） | Redis 8（官方） | Valkey 8 |
| 数据容量 | **250MB** | **~512MB 可用**（1G RAM × maxmemory 50%） | 30MB | 未标注（很小） |
| 命令/吞吐 | **500K 命令/月**，10K cmd/s 峰值 | 无硬性 ops 限（1C 专用 VM） | **100 ops/s** 硬顶 | 未标注 |
| 连接数 | 未标注（serverless 友好） | 常规（未标注） | **30** | 常规（未标注） |
| 月带宽 | 10GB | 含在网络费内（免费层含） | 5GB | 计入工作区额度 |
| 持久化 | ✓ | ✓（单一 DR 备份） | ✓（免费档**无备份/导出**） | **✗ 重启即丢** |
| TLS | ✓ | ✓（+磁盘加密） | ✓ | ✓（外连强制） |
| IP 白名单 | **✗ 免费档无** | —（免费档无 VPC/静态 IP） | ✓（1 条 CIDR） | ✓（外连默认关闭，需显式开） |
| 区域 | AWS/GCP 多区可选 | **不可自选**（Aiven 指定） | AWS/GCP/Azure 可选 | Oregon/Ohio/Virginia/Frankfurt/Singapore |
| 信用卡 | 不需要 | 不需要 | 不需要 | 不需要 |
| 空闲策略 | 无休眠（serverless） | **闲置关机**（提前通知，可再开，数据保留） | **14 天不活跃可删库**（AUP 条款） | 随时可重启（=数据清零） |
| 免费库数量 | 1 | 每 org 每类型 1 个 | 每账户 1 个 | 每工作区 1 个 |
| 升级起步 | PAYG $0.20/10 万命令 | Hobbyist ~$19/月 | Essentials 250MB 起付费（价格未核实） | KV 付费档（价格未核实） |

### 无永久免费层（当日核实，勿再浪费时间）

| 服务商 | 结论 |
|---|---|
| AWS ElastiCache | 旧账户（<2025-07-15）750h cache.t3.micro × 12 个月；新账户仅 $100–200 信用（6 个月）——都是限期试用 |
| GCP Memorystore | 无免费层；最便宜 shared-core-nano 1.4GB ≈ $0.0318/h ≈ $23/月 |
| Azure Cache for Redis | 无免费层，且**全线退役中**（Enterprise 2027-03、Basic/Standard/Premium 2028-09 → Azure Managed Redis，亦无免费层） |
| Dragonfly Cloud | 无永久免费（注册送 $25 试用信用；Flex $36/月起）。自托管 Dragonfly Enterprise 2026-11 起 ≤100 vCPU 免费——但那是自托管 |
| Koyeb | 免费层对新用户已关闭（2026-02 被 Mistral 收购），起步 $29/月 |
| Fly.io | 新组织无免费层（2024-10 取消）；其 Redis 即 Upstash add-on，绕回 Upstash |
| Railway | 仅一次性试用信用（$1–5 口径不一），非永久 |
| Zeabur | 免费档**无持久存储，不能部署数据库服务**；Redis 需 Dev Plan（$5/月） |
| Vercel | 一方 KV 已下线，Marketplace 集成即 Upstash——绕回 Upstash |

## 建议（按场景）

1. **首选 Upstash 免费层**（体验最像 Supabase/Neon：注册即用、TLS、持久化、REST API、区域可选、无休眠）。500K 命令/月 ≈ 平均 19 cmd/s，会话/缓存/限流级用途绰绰有余；250MB 与旧 shared-redis 的 256MB maxmemory 基本等量。**注意免费档无 IP 白名单**——只放缓存/限流类数据，不放敏感数据；消费方应是 VPS 上的服务（选离 VPS 最近的 AWS 区）。
2. **Aiven Valkey Free**：资源最大（~512MB 可用 + 单节点专用 VM + DR 备份 + 磁盘加密），适合"持续有流量"的用途；但区域不可自选（延迟听天由命）且闲置会关机（再开即可，数据保留）——不适合偶尔碰一下的数据。
3. **Redis Cloud 30MB**：只当"官方 Redis 8 兼容性试金石"；30 连接 + 100 ops/s + 14 天不活跃删库，做不了任何正经缓存。
4. **Render KV Free**：不持久化，重启/升级/维护即清零——只适合"丢了也无所谓"的纯缓存，不推荐当主力。
5. **选项 0 别忘了**：本地重建只要 `docker network create shared-infra && cd ~/redis-deploy && docker compose up -d`，代价 384MB 内存。免费云的真实收益是省 VPS 内存 + 免运维 + 多服务共享，不是性能（跨 WAN 往返延迟必然高于本机）。

### 风险与提醒

- 三家免费层均无 SLA（best-effort / community support），不要承载生产关键路径。
- 免费层数字随时间变动（Redis Cloud 2025-12 刚重构过 Essentials 档位；Upstash 从 10K/天改成了 500K/月）；使用前以官方页为准。
- 无中国区域；从大陆桌面直连延迟 150ms+ 且可达性不保证——消费方放在 VPS（直连国际出口）即可规避。
- 与 Supabase 免费层 7 天不活跃暂停不同：Upstash 无休眠、Aiven 关机可再开、Redis Cloud 直接删——三家空闲语义各不相同，选型时按自己的访问频率对号。

## 决策

**2026-11-14 用户决定：暂不迁移/不使用，调研留档备查**（与同日 rakazo→Supabase 调研同样的处置）。将来若要启用，按场景取用调研结论：给 VPS 减负 + hobby 级用量 → Upstash 免费层起步（区域选离 VPS 最近，先实测 ping）；用量以内存为主且访问持续 → Aiven Valkey Free 更宽裕；只是临时要用一下 → 本地拉起 `~/redis-deploy` 最省事（`docker network create shared-infra && cd ~/redis-deploy && docker compose up -d`）。

## 测试计划

纯调研归档，无代码变更，无测试计划。

## 参考

- 详细调研（逐供应商数字与来源）: [free-managed-redis-research.md](./free-managed-redis-research.md)
- 一手来源：Upstash <https://upstash.com/pricing>（含机器可读档）· Redis Cloud Essentials 计划表 <https://redis.io/docs/latest/operate/rc/subscriptions/view-essentials-subscription/essentials-plan-details/> · Aiven Valkey free tier <https://aiven.io/docs/products/valkey/concepts/valkey-free-tier> + <https://aiven.io/pricing/valkey> · Render <https://render.com/docs/free> + <https://render.com/docs/key-value> · AWS <https://aws.amazon.com/elasticache/pricing/> · GCP <https://cloud.google.com/memorystore/valkey/pricing> · Azure <https://azure.microsoft.com/en-us/pricing/details/cache/> + 退役 FAQ · Dragonfly <https://www.dragonflydb.io/pricing> + signup 页 · Zeabur <https://zeabur.com/docs/zh-CN/pricing/free-plan>
- 第三方交叉核对（均 2026-08~11，注意 Upstash 博客利益相关）：layerbase.com《redis-free-tier-comparison》、upstash.com 2026 定价对比两篇、itechguides 2026-08、toolfreebie 2026-08（Koyeb/Northflank）

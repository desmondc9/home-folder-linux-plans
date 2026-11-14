# 免费云托管 Redis/Valkey 调研：逐供应商档案（2026-11-14 在线核实）

核实方法：额度/限制数字优先取**供应商自己的页面**（定价页/官方文档，2026-11-14 抓取）；第三方文章仅做交叉核对并标注发布日期。免费层数字变动频繁，使用前请点开官方页复核。

---

## A. 有永久免费层的（4 家）

### A1. Upstash（最像 "Supabase/Neon of Redis"）

来源：<https://upstash.com/pricing>（2026-11-14 抓取，官方机器可读定价页）

**Free 档**（$0/月，无需信用卡，无时间限制）：

| 项 | 值 |
|---|---|
| 数据容量 | 250MB（FAQ 原文 "Free tier includes 250MB data size and 500K commands per month"） |
| 命令 | **500K 命令/月**（AUTH/HELLO/PING 等运维命令不计费） |
| 峰值吞吐 | 10,000 cmd/sec |
| 带宽 | 10GB/月 |
| 数据库数 | 1 |
| TLS | ✓；持久化 ✓；全球复制 ✓（Primary Replicas） |
| 免费档没有 | IP 白名单、ACL、静态加密（at-rest）、SLA、Insights——都是付费项 |
| 平台/区域 | AWS、GCP（+Vercel），多区域可选 |
| 付费起步 | Pay-as-you-go：$0.20/10 万命令、存储首 1GB 免费、带宽 200GB/月内免费；也可设月度预算封顶 |

其他：
- 付费 Fixed 档从 $10/月（250MB、无限命令）起。
- 有个实验性"agent 即开即用"接口（`POST https://upstash.com/start-redis`，无需注册，3 天内不认领即删）——不适合当正式用途。
- 第三方口径差异：itechguides/layerbase（2026-08）写 "256MB"，以官方页 250MB 为准；历史上免费层曾是 10K 命令/天，现行是 500K/月。

**点评**：注册门槛最低、无休眠、区域可选、REST API 齐全，体验最接近 Supabase/Neon 的"免费层即用"。短板是免费档无 IP 白名单、500K 命令/月的总量上限（≈平均 19 cmd/s）。

### A2. Aiven for Valkey（免费资源最大）

来源：<https://aiven.io/docs/products/valkey/concepts/valkey-free-tier>（官方文档）+ <https://aiven.io/pricing/valkey>

**Free 档**（$0/月，无需信用卡，"indefinitely free of charge"）：

| 项 | 值 |
|---|---|
| 规格 | **1 台专用 VM、1 CPU、1GB RAM**（非共享宿主） |
| 可用数据内存 | `maxmemory` = RAM 50% → **~512MB** |
| 备份 | 单一 DR 备份；监控（指标+日志）含 |
| 安全 | 传输加密 + 磁盘加密 ✓ |
| 限制 | 单节点；无 VPC/静态 IP/integrations/forking/支持工单；不保证 SLA；每 org 每服务类型限 1 个免费实例 |
| **区域** | **不可自选**（定价表 "Clouds: Limited"；文档保留随时更换云/区域的权利） |
| **空闲策略** | **无持续活动会被关机**（提前通知；可随时再开；关机≠删数据） |
| 付费起步 | Hobbyist ~$19/月（同规格可迁） |

**点评**：免费层里唯一给"专用 VM + 真备份"的，~512MB 可用内存也是四家里最大的。两个代价：区域盲盒（延迟不可控）+ 闲置关机（对持续访问的缓存无所谓，对偶尔访问的数据很烦）。产品名是 Valkey 不是 Redis（协议兼容，redis-cli 直连）。

### A3. Redis Cloud Essentials Free（官方 Redis，小号试用）

来源：<https://redis.io/docs/latest/operate/rc/subscriptions/view-essentials-subscription/essentials-plan-details/>（官方文档，2025-12 更新过档位表）；交叉：support.redislabs.com KB（2026-07）、layerbase（2026-08）、saasoffers（2026-11 核对）

**Free 档**（$0/月，无需信用卡，永久）：

| 项 | 值 |
|---|---|
| 容量 | **30MB** |
| 连接 | **30 并发** |
| 吞吐 | **100 ops/s** 硬顶（按 1KiB 请求口径；官方 KB："Free 档固定不可调"） |
| 带宽 | 5GB/月 |
| 其他 | 每账户 1 个免费库；1 条 CIDR 白名单；共享基础设施；社区支持 |
| 免费档没有 | 备份/导出、复制/HA（250MB 付费档起才有） |
| **空闲策略** | AUP 条款：**14 天无活跃可删除数据**（Redis Cloud Agreement 2026-05-15 版；Heroku 渠道口径 30 天）；Redis Insight 2.64 起会在删除前提醒 |

- 付费起步：Essentials 250MB（价格本次未核实具体数）；2025-12 重构过档位表（100MB 档等旧档仍在存量订阅上）。

**点评**：30MB/30 连接/100 ops/s 三个数字两两相乘也做不了正经缓存——官方定位就是 "learning and building test projects"。价值仅在"官方 Redis 8 兼容性验证"。

### A4. Render Key Value Free（不持久化，纯缓存）

来源：<https://render.com/docs/free> + <https://render.com/docs/key-value>（官方文档）

| 项 | 值 |
|---|---|
| 引擎 | Valkey 8（2025-02-12 前创建的旧实例是 Redis 6，不再升级） |
| 数量 | 每工作区 1 个免费实例 |
| 持久化 | **✗ 官方原文 "Free Key Value instances do not continually persist their state to disk... whenever an instance restarts, all of its data is lost"**；升级到付费档也会清数据 |
| 维护/重启 | "Render might restart a Free Key Value instance at any time" |
| 网络 | 外连默认关闭；开启需配 IP 白名单（CIDR）+ TLS（rediss://）；区域 Oregon/Ohio/Virginia/Frankfurt/Singapore |
| 免费档内存大小 | 官方免费档文档未标注（第三方旧口径 ~25MB 级，未证实） |

**点评**：因为不持久化 + 随时可能重启，只能当"丢了无所谓"的缓存。四家里垫底。

---

## B. 无永久免费层的（核实结论）

| 服务商 | 事实 | 来源（2026-11-14） |
|---|---|---|
| **AWS ElastiCache** | 2025-07-15 前注册的旧账户：750h/月 cache.t3.micro × 12 个月（不含 Serverless）；之后的新账户：$100 注册信用 + 至多 $100 任务信用，6 个月内用完。均非永久免费 | aws.amazon.com/elasticache/pricing/ |
| **GCP Memorystore** | 无免费层（free tier 产品清单里没有 Memorystore）；最便宜 Valkey shared-core-nano（1.4GB）$0.0318/h ≈ $23/月。新客户 $300 试用信用 | cloud.google.com/memorystore/valkey/pricing + cloud.google.com/free |
| **Azure Cache for Redis** | 无免费层（Basic C0 250MB 起付费）；且全线退役：Enterprise/Enterprise Flash 2027-03-31、Basic/Standard/Premium 2028-09-30，后继 Azure Managed Redis（亦无免费层）；2026-04-01 起新客户已不能创建 | azure.microsoft.com/en-us/pricing/details/cache/ + learn.microsoft.com 退役 FAQ |
| **Dragonfly Cloud** | 无永久免费；signup 送 $25 试用信用（signup 页原文，第三方有 $100 旧口径）；Flex $36/月起（3GB dev 实例）。自托管 Dragonfly Enterprise 2026-11-04 起 ≤100 vCPU 免费（BSL→新 source-available 许可） | dragonflydb.io/pricing + dragonflydb.cloud/signup + 官方博客 |
| **Koyeb** | 免费层对新用户关闭（2026-02-17 被 Mistral AI 收购；Starter 档将移除），起步 Pro $29/月 | toolfreebie 2026-08 + getstackbill 2026-10（Koyeb 官方 FAQ 口径转述） |
| **Fly.io** | 新组织无免费层（2024-10-07 取消 Hobby/Launch/Scale；官方 FAQ "New organizations don't have a free tier"）；试用 2 VM 小时/7 天；其 Redis 数据服务即 Upstash add-on | fly.io/docs/about/pricing（经 getstackbill/deployhyre 2026-09/10 转述官方 FAQ） |
| **Railway** | 无免费 Redis 额度；一次性试用信用 $1~5（口径不一）即耗尽 | layerbase 2026-08 / deployhyre 2026-09 |
| **Zeabur** | 免费档（serverless）**不支持持久存储，不能部署数据库**（官方文档 "No persistent storage — Cannot deploy services that require persistent volumes (e.g., databases)"）；数据库需 Dev Plan $5/月 | zeabur.com/docs free-plan |
| **Vercel KV** | 一方 KV 已停（转 Marketplace 集成 Upstash） | layerbase 2026-08 |
| **Heroku** | 2022-11 起无免费层 | 公开事实，未另核 |
| **Supabase / Neon** | 均无 Redis 产品（本尊只有 Postgres）——用户类比里的"正主"不提供这个品类 | — |

边缘记录（未深核，仅备查）：Northflank 免费 Sandbox 含 2 服务 + 1 数据库（Redis 可选）+ 2 cron，always-on 不休眠，但注册需验证信用卡（不扣费）；免费档存储/构建分钟数未公开。

---

## C. 结论矩阵

| 需求 | 推荐 |
|---|---|
| 最像 Supabase/Neon 的即开即用体验 | **Upstash**（免费层无白名单是唯一硬伤） |
| 最大化免费内存 + 真备份 | **Aiven Valkey Free**（接受区域盲盒 + 闲置关机） |
| 验证官方 Redis 8 兼容性 | Redis Cloud 30MB（仅此而已） |
| 丢了就丢了的临时缓存 | Render KV Free |
| 偶尔用一下、不想引入外部依赖 | 本地 `~/redis-deploy` 重建（384MB 内存换零外部依赖、零延迟） |
| 想要 AWS/GCP/Azure 生态内托管 | 没有免费的——最便宜合法路径是 GCP nano $23/月 / AWS t4g.micro Valkey ~$9.3/月（付费） |

## D. 变动风险

- Redis Cloud 2025-12 重构 Essentials 档位；Upstash 从 10K/天 → 500K/月；Aiven 保留随时改云/区域/配置的权利；AWS 2025-07 改信用制——**免费层条款 2025~2026 是高频变动区**，部署前一律以官方页当日数字为准。

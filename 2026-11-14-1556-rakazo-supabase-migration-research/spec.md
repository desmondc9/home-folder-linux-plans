# 调研：Rakazo PostgreSQL 迁移到 Supabase（schema 隔离多租户）可行性

- 环境: Bandwagon VPS 上的 rakazo-deploy v0.11.0（Docker compose，本地 PG16，21MB/133 表/3 schema）；调研对象 Supabase Free（2026-11-14 官方文档）
- 日期: 2026-11-14
- 状态: **调研完成，未做任何变更。用户决策（2026-11-14）：暂不执行迁移**——调研结论与 §6 方案骨架保留备用，未来若执行按该骨架走 repo PR + root 脚本 + 切换验证流程。用户设想：免费 Supabase 实例只有一个 → 用 PostgreSQL schema（如 `rakazo`）区分组织多个应用
- 方法: 本机库实证（psql 只读）+ 官方源码调研（Prisma 迁移/RLS/graphile/realtime 实现，repo@main 92eeb44）+ Supabase 官方文档

## 结论（TL;DR）

**用户的「单实例 + schema 隔离」形态：不可行（被 Rakazo 自身架构阻断，除非 fork 上游）。**
**「独占一个 Supabase 项目的整个 public schema」形态：技术上可行（上游官方支持外部托管 PG），但对 Rakazo 这种 DB 密集型应用运营代价显著，不建议。建议维持本地 PG + 建立自动备份。**

## 一、为什么 schema 隔离不可行（三个硬冲突）

1. **授权/RLS 机制硬编码 `public`**（本机实证）：迁移 SQL 含 `GRANT USAGE ON SCHEMA public TO rakazo_app`、`GRANT ... ON ALL TABLES IN SCHEMA public`、`REVOKE CREATE ON SCHEMA public FROM PUBLIC`；实测 `rakazo_app` 的 **502 条表授权 + schema ACL 全部绑定字面量 `public`**。若用 `ALTER ROLE ... SET search_path=rakazo` 把无前缀建表引到别的 schema，这些 GRANT 仍落在空的 public 上 → 应用角色零权限。迁移文件是上游 vendored（每次升级被我们的 Action 整体替换），逐一改写不可维护。
2. **graphile_worker schema 名不可配**（源码实证）：worker 用 stock `graphile_worker` schema，代码无任何 schema 配置项（`packages/adapters/src/wakeup.ts`）。共享实例里这是全局命名空间——与本实例内其他用 graphile 的应用必然冲突，且无法改名。
3. **`REVOKE CREATE ON SCHEMA public FROM PUBLIC` 与 Supabase 平台规则冲突**：Supabase 明文要求不得动 public 的 PUBLIC 授权（其 Auth/Storage/PostgREST 服务依赖）。

另：schema 无嵌套，Rakazo 自身就需要 3 个顶层 schema（public 127 表 + rakazo_private 1 + graphile_worker 5）——「一个 schema 装下 Rakazo」从一开始就不成立。

## 二、官方支持的「外部托管 Postgres」形态（若坚持迁移的唯一可行路径）

源码/文档实证（docs/self-host-configuration.md）：
- 双 URL 模型：`DATABASE_MIGRATION_URL`（owner，跑迁移）+ `DATABASE_URL`（`rakazo_app` 登录，RLS 绑定）；文档明说「migrations run as a role without CREATEROLE, as on some managed Postgres → 自己建登录角色并 `GRANT rakazo_app TO <login>`」——**托管 PG 是官方支持的形态**
- `REALTIME_DATABASE_URL` 就是为「主连接走 pooler、LISTEN 长连接走直连」的托管场景设计的
- 无扩展依赖（仅内置 plpgsql；哈希用内置 sha256，CI 唯一性用 lower() 表达式索引）；realtime 是 LISTEN/NOTIFY（非逻辑复制）；**容器 IPv6 不可达（实测 ENETUNREACH）→ 免费版直连(仅IPv6)不通，走 session 模式 pooler（IPv4，支持预编译语句，LISTEN/NOTIFY 兼容）**
- 连接数：api 4 + worker ≥8 + realtime 1 ≈ 15-20 常驻，在 60 直连/200 pooler 内 ✓

该形态 = **整个 Supabase 项目给 Rakazo 独占**（public + rakazo_private + graphile_worker 三个 schema），不与其他应用共享——与用户「一个免费实例装多个应用」的初衷相反。

## 三、即便独占项目，运营代价（不建议的理由）

| 代价 | 影响 |
|---|---|
| **每 500ms 的 job 轮询跨 WAN**（worker 3 个 host × pollInterval 500ms） | 常驻 6+ QPS 跨洋查询；nano 共享 CPU + RTT → 聊天/任务延迟可感知劣化 |
| 免费版 **7 天低活跃暂停** | VPS 停机一周（或 rakazo 栈故障一周）→ DB 被冻结，恢复需手工 Resume |
| 免费版 **无自动备份** | 数据保障低于本地（本地至少可做 pg_dump + restic） |
| 日常升级迁移走 WAN | migrate 服务 DDL 跨网，升级窗口变长；失败排查面变大 |
| 隐私 | bot 记忆/对话/凭据密文落在第三方免费共享计算上 |
| compose 硬编码内部 `postgres:5432` | 需维护 docker-compose.override.yml（installer 会自动加载 ✓）重写三个 URL + 处理 postgres 服务 depends_on（stub 化）——与上游 compose 演进长期博弈 |

## 四、若未来仍要迁移的路径草图（供参考，非建议）

1. 新建专用 Supabase 项目（区域贴近 VPS）；session pooler 连接串 ×2（owner=postgres / 手建 rakazo 登录角色并 `GRANT rakazo_app`）
2. 本地 `pg_dump`（数据）→ 直连恢复（Supabase 直连 IPv6 从宿主机可用；宿主机有 v6）；先跑 `pnpm db:deploy`（migrate 容器）建结构 + RLS，再导数据
3. 写 `docker-compose.override.yml`：api/worker/migrate 三服务的 DATABASE_URL/DATABASE_MIGRATION_URL/REALTIME_DATABASE_URL 指向 pooler；postgres 服务 stub 化（假 healthcheck）或保留空跑
4. 灰度验证：health `ok:true` + 发消息 + bot 计算机屏显 + graphile 任务消费正常
5. 回退方案：本地栈保留一周可秒切

## 五、建议

维持本地 PG（升级不动卷、数据已实证安全），把「数据安全」诉求转化为**本地自动备份**：每日/每周 `.env` + `pg_dumpall` → `~/atlas-backups`（已有 restic-Azure 备份体系可挂载）。共享 Supabase 免费实例做多租户的目标，适合轻量/无状态应用（reading/books 类），不适合 Rakazo 这种「多 schema + 角色自治 + 高频轮询」的 DB 密集应用。

## 六、追加调研（同日）：迁到本机系统 PostgreSQL 18（Ubuntu 26.04 自带）——✅ 可行且推荐度远高于 Supabase

机器事实（2026-11-14 实测）：Ubuntu **26.04.1**，系统 **PostgreSQL 18.6** 已随系统升级安装并运行（cluster `18/main` @ 5432，仅监听 loopback；空闲无业务库）；5433 空闲；rakazo_app 网络 172.21.0.0/16。

可行性依据：
1. **网络路径实测通**：api 容器 → 宿主 docker0 IP `172.17.0.1:80` 与自身网关 `172.21.0.1:80` 均 OK → PG 监听加 docker0 IP 后容器可达（亚毫秒同机）
2. **上游官方支持外部 DB 双 URL 模式**（同前述）：api/worker 已带 `host.docker.internal:host-gateway` extra_hosts；migrate 服务缺 extra_hosts 需在 override 补
3. **PG16(容器) → PG18(宿主)** 逻辑恢复兼容（pg_dump 21MB）；无扩展依赖；RLS/角色模型在 superuser 下完整可用
4. **数据脱离 compose 卷生命周期**：`down -v` 不再可能删库（真实稳健性收益）；备份直接挂宿主节奏

方案骨架（若执行）：
- PG18 `listen_addresses` 加 `172.17.0.1`（docker0 恒存，不随项目网络重建变化）+ `pg_hba: hostssl/all 172.16.0.0/12 scram-sha-256`（PG 仅监听 loopback+docker0，公网不可达，ufw 兜底）
- `docker-compose.override.yml`（installer 自动加载、升级自动化不覆盖）：api/worker/migrate 三服务 URL → `@host.docker.internal:5432/rakazo`（migrate 补 extra_hosts）+ `postgres` 服务 stub 化（恒真 healthcheck 占位，满足 depends_on）
- 建库建角色（postgres superuser 或按官方托管模式 provisionRuntimeRole 自建）→ `pg_dump -Fc` 容器库 → restore 到宿主 18 → 起 override 栈 → 验证（health/发消息/RLS/graphile 消费）
- 回退：本地 pgdata 卷保留一周，秒切回

代价（比 Supabase 少得多，但如实列出）：override 与官方 compose 形态的长期偏离（pin diff 审查可见）；unattended-upgrades 升级/重启 PG 时 Rakazo 短断连（连接池自动重连）；宿主 PG 多一份需要维护的系统组件（当前空闲，边际成本低）。

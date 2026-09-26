# llm-postgresql 暴力破解告警 — 排查结论与整改记录

> **脱敏声明(2026-09-26 入库前)**:本仓库公开,公司/客户标识、订阅 GUID、全部防御方 IP(家宽/VPS/ACA 出口)已替换为占位符或部分遮蔽;攻击源 IP 保留原文(威胁情报价值)。方法论与流程完整保留。

- **日期**: 2026-09-24
- **跟踪**: Infosec 邮件工单（<Infosec发起人>, 2026-09-24, "Suspected brute-force attack attempts"）
- **订阅**: <公司Azure订阅> (`<公司订阅GUID>`)
- **资源**: `llm-postgresql` (Flexible Server, PG 18, East Asia, RG `<公司RG>`)

## 1. 告警内容

- 攻击源: `121.173.173.48` (韩国), 383 次失败登录, **0 次成功登录**
- 目标账号: `postgres`（数据库级账号）, 客户端应用: `<内部客户端>`

## 2. 排查结论

1. **根因**: 服务器防火墙存在 `AllowAll` 规则 (0.0.0.0–255.255.255.255) 且 `publicNetworkAccess=Enabled`，5432 端口对全网开放，属于邮件中所说的 default network settings。
2. **排除自有脚本**: 攻击 IP 与本人所有出口 IP 均不符（本机上海电信 `114.92.x.x` / 洛杉矶 VPS `104.194.x.x`），确认为外部扫描/暴破，非本人服务所致。
3. **无入侵迹象**: 告警数据 0 次成功登录；未发现攻破证据（建议 Infosec 侧以 Defender 告警时间窗复核）。
4. **日志取证受限**: 服务器未配置 Diagnostic Settings，历史连接日志不可查，只能依赖 Defender 告警数据。

## 3. 合法访问来源盘点（通过 ACA 应用配置反向探测）

引用 `llm-postgresql` 的 Container App（均确认于应用 env 配置）:

| ACA 环境 | 出口静态 IP | 应用 |
|---|---|---|
| `llm-container-app-env-1` (<公司RG>) | `20.187.190.x` | llm-demos-studio-bk, passbolt-app, estimation-tools-bk, work-metrics-collector |
| `skillhub-env` (<公司RG>) | `20.195.90.x` | skillhub-server |
| `<客户ACAenv>` (<客户开发RG>) | `4.152.163.x` | 无引用，不加白 |

## 4. 整改动作（2026-09-24 执行，顺序: 先加白 → 后删全开，业务无中断窗口）

| 动作 | 规则 | IP |
|---|---|---|
| 新增 | `Allow-ACA-llm-env1` | 20.187.190.x/32 |
| 新增 | `Allow-ACA-skillhub-env` | 20.195.90.x/32 |
| 新增 | `Allow-desmond-home` | 114.92.x.x/32（⚠️ 家宽动态 IP，变更需手动更新） |
| 新增 | `Allow-desmond-vps` | 104.194.x.x/32 |
| 删除 | `AllowAll` | 0.0.0.0–255.255.255.255 |
| 保留 | `AllowAzureServices` | 0.0.0.0（当前无 VNet/Private Endpoint，保留以兜底其他 Azure 服务；见跟进项） |

整改后验证: 规则列表仅剩上述 5 条；本机到 `llm-postgresql.postgres.database.azure.com:5432` TCP 可达。

## 5. 跟进项（未完成，建议排期）

1. **Diagnostic Settings → Log Analytics**: 未配置，下次事件无法自查连接日志（本次排查已受此限制）。
2. **Entra (AAD) 认证**: 邮件建议项，可消除数据库级密码暴破面。
3. **Private Endpoint + 关闭公网访问**: 更彻底的方案（IT 邮件 "restrict to VPN/Bastion" 的终态方向），ACA 同区域可用 VNet 集成。
4. **AllowAzureServices (0.0.0.0) 去留**: 过渡期保留；若确认所有客户端均已显式加白/VNet 化，可删除。
5. **家宽 IP 变更**: 114.92.x.x 为动态 IP，变更后 `Allow-desmond-home` 需同步更新（连不上 DB 时先查这个）。
6. **Defender for Cloud 扫描/建议启用**: 权限在 Infosec，回复邮件时确认由其执行或授予所需权限。

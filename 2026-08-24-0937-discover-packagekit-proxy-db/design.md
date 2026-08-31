# Discover/apt 代理错误修复 — PackageKit 持久化代理数据库

- 日期：2026-08-24
- 主机：desmond-yaoshi15proseriesgm5ix0a (Kubuntu 26.04, kernel 7.0.0-30)
- 状态：✅ 已修复并端到端验证

## 背景

切换 sing-box TPROXY 透明代理（v2rayN 下线，`127.0.0.1:10808` 不再监听）后，
Discover 每次刷新报全部 22 个第三方源失败：

```
E: https://packages.cloud.google.com/apt cloud-sdk InRelease is not (yet) available
   (Unable to connect to 127.0.0.1:10808:)
...（1password / k8s / hashicorp / microsoft / google / ustc 镜像等 22 源同错）
```

## 现象与排查路径（逐环证据）

| 层 | 检查 | 结果 |
|---|---|---|
| 端口 | `ss -tlnp` | 10808 无监听（仅 sing-box mixed 10809）→ 报错端口确实死了 |
| apt 配置 | `apt-config dump`、全 `/etc/apt`、`rg 10808 /etc/` | 全干净，无任何代理 |
| 系统环境 | `systemctl show-environment`、PK unit、env generators | 全干净 |
| KDE 代理 | `~/.config/kioslaverc` | 有 4 条 10808 残值 → **清除后重启 Discover 无效（假设证伪）** |
| CLI 对照 | 8/23 21:45 终端 `apt upgrade` 成功 | root apt 无代理 → 问题只存在于 PackageKit 进程内 |
| apt method 实验 | 手动驱动 `/usr/lib/apt/methods/https`（apt method 协议 601/600 报文） | 带 `http_proxy` 环境变量 → 连 127.0.0.1；无变量 → 直连成功。证明 apt method 服从代理注入 |
| 二进制取证 | `packagekitd` strings | `SetProxy method called`、`pk_transaction_db_set_proxy`、SQL `INSERT INTO proxy (…proxy_http…)`、`SELECT * FROM proxy LIMIT 1` |
| **数据库实锤** | `sqlite3 /var/lib/PackageKit/transactions.db "SELECT * FROM proxy"` | **10 行 `http://127.0.0.1:10808`，uid 1000，按 logind session 插入，时间 2025-12-28 ~ 2026-05-08** |

## 根因链

1. 2025-12 ~ 2026-05：Discover 每个会话通过 D-Bus `org.freedesktop.PackageKit.SetProxy`
   上报当时有效的代理，PackageKit 持久化进 `/var/lib/PackageKit/transactions.db` 的 `proxy` 表
2. 2026-05-08 后上报方沉默（Plasma/Discover 升级行为变化），但查询是 `… LIMIT 1` 兜底读最后一行
3. 2026-08 中旬 v2rayN → sing-box，10808 死亡 → 每次事务 PackageKit 把死代理注入
   apt acquire（`pk_backend_job_get_proxy_http`）→ 全源 connection refused
4. 该代理与 kioslaverc / apt.conf / systemd 环境完全脱钩 —— 清系统配置全部无效的原因

## 修复

```bash
sudo sqlite3 /var/lib/PackageKit/transactions.db "DELETE FROM proxy;"
sudo systemctl restart packagekit
# 重启 Discover 验证
```

验证：`refresh-cache transaction … finished with success after 6787ms`，22 源全绿，零
`Unable to connect`。sing-box TPROXY 透明接管 apt 直连，无需显式代理。

## 附带清理

- `~/.config/kioslaverc`：删除 4 条死代理残值（httpProxy/httpsProxy/ftpProxy/socksProxy
  = 10808；Chromium 系浏览器也读此文件），备份于 `~/.config/kioslaverc.bak-20260824`。
  `ProxyType=0` + NoProxyFor 保留。

## 经验/深坑

- **PackageKit 有自己的代理持久化存储**，与系统代理配置无关；Discover 报
  "Unable to connect to <代理>" 时先查 `proxy` 表：`sudo sqlite3
  /var/lib/PackageKit/transactions.db "SELECT * FROM proxy;"`
- apt 官方 CLI 不读 `http_proxy` 环境变量，但 **apt method（http/https）在被父进程
  （此处为 PackageKit 注入的 acquire 配置）告知代理时同样服从**——手动驱动
  `/usr/lib/apt/methods/https`（601 Configuration / 600 URI Acquire 报文）是免 root
  判别"代理来自哪一层"的好工具
- `pkill -f plasma-discover` 会匹配到自己 shell 的命令行 → 自杀（exit 144）；
  用 `pgrep -x plasma-discover` 精确匹配
- `pkcon` 在此机未安装（packagekit-tools），控制实验用 Discover 启动时自动
  refresh-cache + `journalctl -u packagekit` 观察即可

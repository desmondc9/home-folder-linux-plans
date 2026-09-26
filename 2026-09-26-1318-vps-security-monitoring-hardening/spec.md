# 搬瓦工 VPS 安全监控与应急响应 — 调研 + 第 1 档加固

> 日期：2026-09-26 13:18 ｜ 类型：调查审计 + 基础设施加固（无 repo 代码变更，无 PR）
> 完整调研报告（含暴露面明细、工具对比、应急预案、复现命令）：`~/docs/vps-security-monitoring-research.md`

## 背景与目标

用户要求对所住的搬瓦工 VPS（Ubuntu 24.04.4，8GB RAM，公网 IP 直挂 eth0，跑 Docker 应用栈 + 代理/组网栈）做**攻击早期发现能力**调研，并 brainstorm 监控与应对方案。随后拍板实施第 1 档速赢项。

## 范围

- **in**：本机只读侦察（暴露面/日志/进程/防火墙/版本）、依赖栈安全通告核查、监控方案设计、第 1 档实施（告警通道 + 自动更新 + fail2ban 扩展 + 日志保留 + 端口漂移检测 + 三个组件版本升级）
- **out**：第 2 档（CrowdSec/AIDE/Lynis，用一两周后评估）、第 3 档（Wazuh 单机）、6001 收紧、authorized_keys 收敛、应用层（Kratos/Hydra）自身的认证加固

## 现状分析（2026-09-26 实测）

**底子好**：SSH 密钥-only + 禁 root；ufw 默认 DROP 且规则精细（openclaw 仅 tailnet）；Docker 容器全绑 127.0.0.1；VLESS-REALITY 抗探测；derper `-verify-clients`；frp 强 token；入侵迹象检查干净（成功登录全部来自本人 `240e:` IPv6）。

**缺口**（按严重度）：🔴 自动安全更新实际关闭（`APT::Periodic::Unattended-Upgrade "0"`）；🟠 零告警触达；🟠 Web 层无检测；🟡 日志保留短且全在本机；🟡 无 FIM/rootkit 检测；🟡 authorized_keys 10 把无 `from=`；🟡 6001 公网直达家庭 Win11 SSH。

**版本差距**：frps 0.70.0（GHSA-26gq-p25f-99cp 未认证 RDoS 通告范围内，但本机未启用 sshTunnelGateway）；headscale 0.29.3→0.29.4（OIDC 加固）；sing-box 1.13.7→1.14.2。

**噪音基线**：wtmp 自 4 月起 40,071 次失败登录（典型互联网背景扫描，密钥-only 下无成功可能）。

## 方案设计（三档，详见 docs 报告 §2）

- **第 1 档（<100MB）**：ntfy 告警通道 + 自动安全更新 + 每日摘要 + fail2ban nginx/recidive jail + 日志保留 + 端口漂移检测 ← **本次实施**
- **第 2 档（+200-400MB，推荐后续）**：CrowdSec + AIDE 每晚 FIM + Lynis 季度自检
- **第 3 档（+1.5-2GB）**：Wazuh 单机一体 + 远程日志转发 + osquery + 外部拨测

## 用户决策（2026-09-26）

1. 实施档位：**第 1 档速赢项**（先跑一两周再评估第 2 档）
2. 告警通道：**自托管 ntfy**（走现有 nginx + 域名，数据不出自有设施）
3. 速赢修复：**都做**（自动更新 + 三个组件版本升级）

## 验收标准

- [x] ntfy 端到端可发布/订阅（token 认证，deny-all 默认策略）
- [x] `APT::Periodic::Unattended-Upgrade "1"`，首轮 unattended-upgrade 执行
- [x] fail2ban 4 jail active（sshd + nginx×2 + recidive）
- [x] 公网端口基线建立，漂移可触发推送
- [x] frps/headscale/sing-box 升级后全部 active 且端口在听
- [x] 每日摘要 08:30 推送（次日人工确认手机收到 = 链路最终验收）

## 遗留与后续

1. 第 2 档三件套（建议 10 月中旬评估）
2. 6001（frp 转发 Win11 SSH）是否改走 Tailscale
3. authorized_keys 收敛 + 关键钥匙 `from=`
4. 手机端 ntfy 订阅（用户本人操作，凭据 `/root/ntfy-credentials.txt`）

## 附：本任务衍生的其他产出

- MCP web-search-prime 挂起问题诊断：根因为 api.z.ai 后端临时 500 + 同 session 并发突发；配置无需改动，结论为"远程 MCP 串行调用"。过程记录在 opencode 会话 ses_f24606999ffeCarWaz1ujnb3zR。

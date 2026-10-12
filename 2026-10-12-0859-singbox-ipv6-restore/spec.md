# Windows sing-box 恢复 IPv6 与 IPv6 优先解析

- 日期: 2026-10-12（Asia/Shanghai）
- 环境: Windows 11 笔记本，有线 RJ45 连接小米 AX6000；Wi-Fi 断开；sing-box 1.14.2 / Windows amd64，由 NSSM 的 `sing-box` 服务管理；档案存于 WSL Ubuntu 的 `~/plans`。
- 状态: 已应用，Chrome test-ipv6.com 全部八项通过；IPv6 故障回退与长期稳定性未验证。
- 关联: [AX6000 历史故障](../2026-09-17-0915-ipv6-ax6000-ra-outage/spec.md)、[实施记录](implementation.md)。

## 背景与目标

关闭 sing-box 时 Chrome 的 IPv6 检测通过，开启时失败。用户改用 RJ45，并要求复核 `D:\Desmond\Apps\sing-box\config.json`，恢复 IPv6，优先 IPv6，同时保留 IPv4。

## 诊断结论

实际配置包含 `query_type: AAAA / action: reject`，且 `dns.strategy` 为 `prefer_ipv4`。TUN DNS 查询收到 Query refused；HTTP 代理自行解析时却可访问 IPv6-only 的 api6.ipify.org，证明代理服务器具有 IPv6 出口。当前失败的明确原因是 AAAA 拦截，源于 9 月故障时的客户端保护措施。

以太网已有公网 IPv6 地址与 IPv6 默认网关。有线可绕开无线链路问题，但无法据此证明 AX6000 历史 RA/PD 故障已消失。开启代理后的公网检测体现代理服务器出口，不能用来证明本地运营商 IPv6 长期正常。

## 方案与验收边界

删除 AAAA 拦截；DNS 改为 `prefer_ipv6`；在路由 DNS 劫持和 UDP 443 拒绝规则之后、普通分流规则之前添加 `resolve / strategy: prefer_ipv6`，对域名目的地址按 DNS 分流规则解析。保留现有 TUN 双栈地址、分流规则与 VLESS 服务器 IPv4 地址。

双栈优先与 IPv4-only 可达已经验证；没有人为制造 IPv6 黑洞，因此不能宣称故障时自动回退已通过，尤其不能把 TUN 本地握手视作外部 IPv6 成功。纯 IPv6 目标本身没有 IPv4 地址可供回退。

官方说明: https://sing-box.sagernet.org/configuration/route/rule_action/#resolve

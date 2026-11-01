# Tailscale 安全通告调研 + 客户端升级（TS-2026-013 / Tailworm）

> 日期：2026-11-01 14:47 ｜ 类型：安全调研 + 组件升级（VPS 本机操作，无 repo 代码变更）
> 前置关联：`2026-09-26-1318-vps-security-monitoring-hardening/`（第 1 档加固与告警通道）

## 背景与目标

用户要求排查近期 Tailscale 公开安全问题的披露情况、评估本机（搬瓦工 VPS，tailscaled 节点 brave-goose-1 / 100.64.0.4，exit node 提供方）是否受影响，并升级修复。

## 调研结论（来源均为一手渠道，2026-11-01 查证）

| 披露 | 内容 | 本机评估 |
|---|---|---|
| **TS-2026-013**（官方 bulletins 页） | eMudhra TLS 中间证书私钥泄露；**< v1.104.2 的客户端**不含 Go 1.27.3 的 distrust 列表，控制面 TLS 校验可被伪造证书欺骗；WireGuard mesh 数据面不受影响 | ⚠️ 本机 1.102.3 在范围内 → **升级** |
| **Tailworm**（官方博客，修复于 **v1.104.4**，2026-10 下旬） | Tailscale SSH 授权后会话的权限边界 4 处缺陷（含 socket 转发滥用提权 root）；利用前提 = 攻击者已持有 tailnet 授权设备 + ACL 明确允许 + 目标运行 Tailscale SSH 服务端 | ✅ 本机 `RunSSH: false`，非目标；升级即免疫 |
| TS-2026-012 | libtailscale（Swift/Ruby/Python 嵌入式库）SCM_RIGHTS 对端地址错配 | ✅ 不适用（标准 Linux daemon） |
| CVE-2026-107060 | Android 客户端（versionCode 297862600）VPN 配置权限问题 | ✅ 不适用本机；用户 Android 设备留意商店更新 |
| CVE-2026-57999 | luci-app-tailscale（OpenWrt）RCE | ✅ 不适用 |

来源：
- https://tailscale.com/security-bulletins （TS-2026-013 / 012 原文）
- https://tailscale.com/blog/tailscale-ssh-findings-fixes （Tailworm 官方回应与利用前提）

## 决策

用户指示直接升级修复（本会话内确认）。目标版本 **v1.104.4**（apt 源 candidate，同时覆盖 013 与 Tailworm）。

## 验收标准

- [x] tailscale 1.104.4，tailscaled active，节点重连，tailscale0 接口/IP 不变，exit node 正常
- [x] 根因修复：Tailscale 第三方源纳入 unattended-upgrades（此前该源不在默认 Allowed-Origins，导致客户端自 8 月起停留在 1.102.3）
- [ ] 用户其他 tailnet 设备（Win11 桌面 / 2 台 iPad，离线 42-49 天）上线后更新各自客户端

## 风险与回滚

- apt 官方源滚动升级，回滚 = `apt install tailscale=1.102.3`（旧版仍在 apt 缓存/可从 pkgs.tailscale.com 取）
- tailscaled 随包重启，tailnet 闪断秒级自愈（已验证）

# 实施记录 — Tailscale 安全升级（2026-11-01 14:40–14:47 CST，全部完成）

## 任务清单

- [x] 本机现状核查：1.102.3（2026-08-20）、apt 官方源安装、`RunSSH: false`、节点 brave-goose-1 在线供 exit node
- [x] 调研：官方 security-bulletins + Tailworm 博客（web-reader）+ NVD/搜索（MCP 串行调用）；GitHub advisory API 对 tailscale/tailscale 为 404（其不使用该渠道），release notes 不含安全字样（其惯例）
- [x] 升级 1.102.3 → 1.104.4 并验证
- [x] 根因修复：tailscale 源纳入 unattended-upgrades
- [x] ntfy 推送升级记录（顺带验证 9 月建的告警通道存活）

## 变更明细

| 路径 | 变更 | 回滚 |
|---|---|---|
| 包 `tailscale`（apt, `pkgs.tailscale.com/stable/ubuntu noble`） | 1.102.3 → **1.104.4** | `apt install tailscale=1.102.3` |
| `/etc/apt/apt.conf.d/51unattended-upgrades-tailscale`（新增） | `Unattended-Upgrade::Allowed-Origins { "Tailscale:stable"; }` | 删除该文件 |

无配置/密钥/ufw 变更。

## 验证记录（2026-11-01 14:44）

- `tailscale version` = 1.104.4；`systemctl is-active tailscaled` = active
- `tailscale status`：节点重连，peers 列表正常；`tailscale0` = 100.64.0.4/32（IP 不变）
- `unattended-upgrade --dry-run --debug`：Allowed origins 含 `o=Tailscale,a=stable`
- ntfy `alerts` 主题实收：「✅ Tailscale 安全升级完成」（id `soy5a2ODZ8Sf`）

## 待人工确认

- [ ] 其他 tailnet 设备上线后更新客户端：desktop-j7nbnu4（Win11）、desmond-ipad / desmond-ipad-sfi（TS-2026-013 同样适用；Android 设备另含 CVE-2026-107060）

## 性能影响

无新增常驻进程；纯包升级 + 一行 apt 配置。

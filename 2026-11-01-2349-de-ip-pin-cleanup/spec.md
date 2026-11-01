# 换 IP 后的去硬编码：DERP 改域名、CI 探测改域名

- 环境：Bandwagon VPS，IPv4 已由 104.194.83.82 更换为 **95.169.0.65**（2026-11-01，旧 IP 被单向黑洞，见 [ipv4-reality-unreachable](../2026-11-01-1443-ipv4-reality-unreachable/spec.md)）；IPv6 不变。
- 日期：2026-11-01 深夜。
- 用户要求：① headscale DERP 不再写死 IP（用域名）；② signal-align-umbrella 的 workflow 同理。

## DNS 现状核实（只读）

- signal-align.com zone：仅 `bandwagon`（及顶点）为 A 记录 → 95.169.0.65（灰云）；vs/derp/headscale/ntfy/auth/identity/login/laptop 全是 CNAME → bandwagon。
- desmondchen.com zone：api.books/api.reading 灰云 CNAME → bandwagon；books/reading 前端橙云 CNAME → bandwagon（CF 回源自动跟随）。
- 结论：换 IP 只需改 bandwagon 的 A 记录一处（用户已做），全套域名自动跟随——这正是"用域名代替 IP"的基础。

## 1. headscale DERP 改域名（本机）

- 背景：Tailscale DERP 地图中节点的 `ipv4:`/`ipv6:` 是可选"IP 覆盖"；不填则客户端按 `HostName` 走 DNS。
- 改动（root 私有备份：`/var/backups/headscale-derp-domain/2026-11-01-234905/`）：
  - `/etc/headscale/config.yaml`：删除 `derp.server.ipv4: 104.194.83.82`（embedded region 999 的 HostName 由 `server_url: https://bandwagon.signal-align.com` 得出）。
  - `/etc/headscale/derp-standalone.yaml`：删除 region 998 节点的 `ipv4:`/`ipv6:` 两行（HostName=derp.signal-align.com）。
- 重启 headscale 后验证：服务 active；日志显示 embedded 节点为 `HostName:bandwagon.signal-align.com IPv4: IPv6:`（空）；节点 brave-goose-1 1 秒内重连；`/derp/probe` 经 nginx 与公网 DNS 均 HTTP 200；`/etc` 中旧 IP 引用清零。
- derper 本体无需重启（按 wildcard 监听 8443/3479，不读地图文件）。
- UFW 3478/3479 无需改动。

## 2. signal-align-umbrella workflow 改域名（仓库 PR）

- 问题：`vps-deploy.yml` 与 `cd.yml` 的健康探测用 `curl --resolve <host>:443:104.194.83.82` 钉死旧 IP，下次 Release/CD 必失败。
- 修复（[#70](https://github.com/desmondc9/signal-align-umbrella/issues/70) / [PR #71](https://github.com/desmondc9/signal-align-umbrella/pull/71)，squash 合并为 `c1571db`）：删 `VPS_IP` 与 `--resolve`，直接 `curl https://<host>.signal-align.com/...`；README 的旧 IP 改为主机名。CI 绿（changes pass，其余按路径跳过）。
- 权衡：探测从"DNS 无关"变为依赖公共 DNS——因 DNS 由用户在 Cloudflare 掌控且结构已收敛到单一 A 记录，接受此取舍。按仓库规则走分支→PR→CI→合并，未直推 main。

## 遗留与注意

- 之前取消的 phase-2 worktree（`feature/singbox-vps-edge-transaction`，含未提交废案代码）仍存在于 opencode worktree 目录，未动；是否清理待用户决定。
- 换 IP 后 `/var/backups` 中各备份的恢复说明仍指旧 IP，仅作历史档案，无需改写。
- 以后再换 IP 的标准动作：Bandwagon 换 IP → Cloudflare 改 `bandwagon` A 记录（AAAA 若变则一并）→ 完事；DERP/CI/客户端无需再改。

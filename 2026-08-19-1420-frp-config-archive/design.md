# 本机 frp 客户端配置档案

日期:2026-08-19(归档日;配置本身 2026-07 建、2026-08-18 扩展 Sunshine 端口) · 状态:线上生效中

本目录是**本机 frp 配置的实体快照与说明**。配置曾被文字引用在串流档案里,2026-08-19 借清理 Cloudflare Zero Trust 之机把实体文件归档入库(最初误放在 [../2026-08-19-1414-cloudflare-zerotrust-removal/](../2026-08-19-1414-cloudflare-zerotrust-removal/) 内,同日应要求移出独立成档)。

## 架构

```
本机 (frpc)                                    bandwagon VPS (frps)
/etc/frp/frpc.toml ──出站 TCP──> bandwagon.signal-align.com:7000 (token auth)
      │                                        │
      ├─ 127.0.0.1:22      <── :6000 ──────────┤   外网 SSH
      └─ Sunshine 端口     <── 同端口 ──────────┤   Moonlight 串流备份链路
```

- 客户端:`/usr/local/bin/frpc -c /etc/frp/frpc.toml`,systemd `frpc.service`(enabled, running)
- 服务端:bandwagon VPS(`104.194.83.82` / `2607:8700:5500:7bd3::2`),`frps.service`,`bindPort=7000`,token auth;ufw 放行 7000(控制面)+ 各 remotePort
- DNS:`laptop.signal-align.com`、`bandwagon.signal-align.com` 均为 **A 记录灰云(DNS-only)** 指 VPS——Cloudflare 免费版只代理 80/443,frp 的任意 TCP/UDP 端口必须绕开橙云,SSH/串流流量实际不过 CF 边缘

## 文件快照(机密已脱敏,其余与线上一致)

> **2026-08-19 安全变更**:本仓库实为 GitHub **公开仓库**,`auth.token` 曾随归档泄露,已从全部 git 历史清除(filter-repo 强推)并轮换,详见 [../2026-08-19-1528-frp-token-redaction/](../2026-08-19-1528-frp-token-redaction/)。快照中的 `__FRP_TOKEN_REDACTED__` 为占位符,真实 token 只存在于线上 0600 root 文件中。

| 本目录 | 线上位置 | 权限 |
|---|---|---|
| [frpc.toml](frpc.toml) | 本机 `/etc/frp/frpc.toml` | 线上 0600 root 含 `auth.token`;快照已脱敏 |
| [frpc.service](frpc.service) | 本机 `/etc/systemd/system/frpc.service` | 0644 root |
| [frps.toml](frps.toml) | VPS `/etc/frp/frps.toml` | 线上含同一个 `auth.token`;快照已脱敏 |
| [frps.service](frps.service) | VPS `/etc/systemd/system/frps.service` | |

VPS 侧要点:

- `bindPort = 7000`(frpc 控制面入口);`auth.token` 与本机 `frpc.toml` 一致——**改 token 必须两端同改**。
- `allowPorts` 白名单:`6000-6010`(SSH 预留区间,现役用 6000)+ `47984` / `47989` / `47998-48002` / `48010`(Sunshine)。frpc 申请范围外端口会被 frps 直接拒绝,**新增代理端口要先加白名单**。
- `frps.service` 以 `User=nobody` + `NoNewPrivileges=true` 运行(最小权限);`After=network.target`(客户端用的是 `network-online.target`,服务端不等网络就绪,先起无妨)。
- 防火墙:VPS 上 ufw 默认 deny 入向,显式放行 7000/tcp + allowPorts 里的各端口(无云安全组,ufw 是唯一防火墙层)。
- VPS sudo 需密码,凭据在 `~/.bandwagon/credentials.jsonc`;SSH 入口 `ssh desmond@bandwagon.signal-align.com`(22 端口直连 IP 不通)。

## 代理矩阵(frpc.toml 内容速览)

| name | type | local | remote | 用途 |
|---|---|---|---|---|
| kubuntu-ssh | tcp | 127.0.0.1:22 | :6000 | 外网 SSH:`ssh -p 6000 desmond@laptop.signal-align.com` |
| sunshine-tcp-47984 | tcp | 127.0.0.1:47984 | :47984 | Moonlight:HTTPS API |
| sunshine-tcp-47989 | tcp | 127.0.0.1:47989 | :47989 | Moonlight:RTSP |
| sunshine-tcp-48010 | tcp | 127.0.0.1:48010 | :48010 | Moonlight:控制 |
| sunshine-udp-47998 | udp | 127.0.0.1:47998 | :47998 | Moonlight:视频 |
| sunshine-udp-47999 | udp | 127.0.0.1:47999 | :47999 | Moonlight:控制 |
| sunshine-udp-48000 | udp | 127.0.0.1:48000 | :48000 | Moonlight:音频 |
| sunshine-udp-48002 | udp | 127.0.0.1:48002 | :48002 | Moonlight:麦克风 |
| sunshine-udp-48010 | udp | 127.0.0.1:48010 | :48010 | Moonlight:RTSP |

transport 调优(相对默认值):`tcpMuxKeepaliveInterval = 10`(yamux 心跳,默认 30s)、`dialServerKeepAlive = 30`(frpc↔frps 底层 TCP 的 SO_KEEPALIVE,默认 7200s 太长,NAT 会话早夭时无法及时感知断线)。

## 日常运维

- 改本机配置后:`sudo systemctl restart frpc`(Restart=on-failure,5s 间隔,不怕误杀)
- 改 VPS 配置后:VPS 上 `sudo systemctl restart frps`;查日志 `journalctl -u frps -f`
- 本机查日志:`journalctl -u frpc -f`
- **新增代理端口流程**:VPS `frps.toml` 的 `allowPorts` 加白名单 + ufw 放行 → 本机 `frpc.toml` 加 `[[proxies]]` → 两端各自 restart
- 验证链路:外网设备 `ssh -p 6000 desmond@laptop.signal-align.com`;Moonlight 里主机 `laptop.signal-align.com`(与 LAN/tailnet 条目自动合并为同一图标)
- 升级 frp:从能自由出网的机器查 `https://api.github.com/repos/fatedier/frp/releases/latest` 拿版本号,客户端/服务端版本保持一致
- 主链路是 tailnet(见下),frp 是备份链路;两条都依赖 sing-box 分流配置里的 `custom-direct.json`(signal-align.com + VPS IP 强制直连),改分流规则时勿动

## 参考

- [../2026-08-19-1302-sunshine-moonlight-tailnet/](../2026-08-19-1302-sunshine-moonlight-tailnet/) —— 串流双链路(frp 备份 + tailnet 主)部署记录
- [../2026-08-19-1414-cloudflare-zerotrust-removal/](../2026-08-19-1414-cloudflare-zerotrust-removal/) —— 同日清理 CF Zero Trust;frp 是 SSH 入向的现役方案
- 记忆:`moonlight-sunshine-tailscale-setup`、`cloudflare-tunnel-ssh-client`(含 VPS 侧 frps 细节)

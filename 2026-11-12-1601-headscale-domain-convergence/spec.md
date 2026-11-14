# headscale 控制面域名收敛(bandwagon → headscale.signal-align.com)

日期: 2026-11-12 · 状态: 已完成 · 实施记录: [implementation.md](implementation.md)
- 环境: Bandwagon VPS brave-goose-1(95.169.0.65),headscale v0.29.3 @ 127.0.0.1:8080,nginx 1.24 前置(stream 443 SNI 分流 → 127.0.0.1:14443)
- 前置任务: [2026-09-22-1956-win11-tailnet-join](../2026-09-22-1956-win11-tailnet-join/)(新域名入口的建立,当时明确保留旧入口)

## 背景与目标

2026-09-22 起 headscale 同时服务两个域名(vhost `headscale` = bandwagon.signal-align.com 旧入口,vhost `headscale-new` = headscale.signal-align.com 规范入口),同一后端。本次收敛为单一域名。

目标:
1. `server_url` → `https://headscale.signal-align.com`(内嵌 DERP region 999 地址一并切换)
2. vhost 收敛为单文件 `headscale`(即现 headscale-new 内容,更新注释),移除旧软链与旧文件
3. VPS 自身节点(id 4)重指新域名,节点身份/IP 不变
4. 删除 bandwagon 证书及续期配置
5. 离线节点(7 个)记录保留,设备侧改指方式记录在 implementation.md

## 现状核查结论(2026-11-12 实测)

| 项 | 结论 |
|---|---|
| 新域名链路 | `https://headscale.signal-align.com/health` = 200,DNS 为 CNAME→bandwagon A→95.169.0.65(CF 灰云) |
| sing-box 443 分流 | 仅 SNI=www.cloudflare.com 进 REALITY(24444),**default 全部进 nginx 14443**,与域名收敛无关 |
| 节点 | 在线: id 4 brave-goose-1(ControlURL=旧域名)、id 10 yaoshi15pro-win(注册即新域名);离线 7 个 |
| DERP | 内嵌 999 由 server_url 派生;standalone 998 = derp.signal-align.com 独立域名,不受影响 |
| bandwagon 证书引用 | 仅旧 headscale vhost;其余 vhost 各自独立证书;全机无其他服务依赖该 HTTPS 入口 |

## 用户决策(2026-11-12 确认)

1. 离线节点:直接删旧 vhost,节点记录保留,设备下次用时手动改指
2. bandwagon 证书:删除(certbot delete)
3. 文件命名:headscale-new 改名为 headscale

## 风险与回退

- headscale 重启约 1–2 秒控制面闪断,在线节点自动重连,WireGuard 数据面不受影响
- 回退:备份在 `~/Backups/headscale-convergence-2026-11-12/`(config.yaml、两个 vhost、证书续期配置);恢复 vhost + server_url 后 certbot 重新签发 bandwagon 证书即可

## 验收标准

- [x] `server_url` 为新域名,headscale active,/health 双路径验证(新 200)
- [x] VPS 节点 ControlURL = 新域名,tailscale status 在线,节点 id 4 / 100.64.0.4 不变
- [x] sites-enabled 仅一个 headscale 软链;nginx -t 通过;新域名 /health 200
- [x] certbot certificates 无 bandwagon 条目
- [x] 证书续期定时器对其余证书无影响(各 vhost + 80 端口 server 块均未触碰)

# 实施记录 — 第 1 档加固（全部完成于 2026-09-26 13:00–13:20 CST）

## 任务清单

- [x] 侦察：暴露面（ss/ufw 交叉）、sshd 有效配置、日志、进程、cron、authorized_keys（结论见 spec.md / docs 报告）
- [x] 调研：GitHub Advisory API 直查 + MCP 搜索（MCP 故障及结论见 spec.md 附录）
- [x] ntfy 告警通道部署 + E2E 验证
- [x] 自动安全更新开启 + 首轮执行（后台运行中，结果由次日摘要体现）
- [x] 每日安全摘要脚本 + cron
- [x] fail2ban 扩展（nginx-botsearch / nginx-bad-request / recidive + ntfy action）
- [x] 日志保留（rsyslog rotate 14 / journald SystemMaxUse=1G）
- [x] 端口漂移检测（每小时 + 基线 + 周日心跳）
- [x] 版本升级：frps 0.71.0 / headscale 0.29.4 / sing-box 1.14.2

## 变更明细

### 新增

| 路径 | 内容 |
|---|---|
| `~/ntfy/` | compose（镜像 `binwiederhier/ntfy:v2.28.0`，仅绑 `127.0.0.1:2599`）+ `etc/ntfy.yml`（deny-all + behind-proxy）|
| `/etc/nginx/sites-available/ntfy` (+enabled 软链) | vhost，SSE 友好（`proxy_buffering off`、3600s 超时），证书 `/etc/letsencrypt/live/ntfy.signal-align.com/` |
| Cloudflare DNS | `ntfy.signal-align.com` A → 104.194.83.82（DNS-only，对齐现有记录）|
| `/root/ntfy-credentials.txt` (0600) | admin 密码 + `tk_` token + 订阅 URL |
| `/root/.ntfy-token` (0600) | 脚本用 token |
| `/usr/local/bin/security-digest.sh` + `/etc/cron.d/security-digest` | 每日 08:30 摘要 → ntfy（包/重启/封禁/资源/心跳）|
| `/etc/fail2ban/jail.d/01-custom.local` | nginx 两 jail（access.log，封 1h）+ recidive（封 1w，allports nftables）；ignoreip 含 tailnet `100.64.0.0/10` |
| `/etc/fail2ban/action.d/ntfy.conf` (600) | recidive 封禁时推送 ntfy |
| `/usr/local/bin/port-drift-check.sh` + `/etc/cron.d/port-drift` | 每小时公网监听与 `/var/lib/port-drift/baseline.txt` diff，漂移推送并自动更新基线；周日心跳 |

### 修改

| 路径 | 变更 | 回滚 |
|---|---|---|
| `/etc/apt/apt.conf.d/20auto-upgrades` | `Unattended-Upgrade "0"` → `"1"` | 改回 `"0"` |
| `/etc/logrotate.d/rsyslog` | `rotate 4` → `rotate 14` | 改回 |
| `/etc/systemd/journald.conf.d/99-size.conf` | 新增 `SystemMaxUse=1G`（journald 已重启生效） | 删文件重启 journald |
| `/usr/local/bin/frps` | 0.70.0 → 0.71.0 | `frps.bak-v0.70.0` |
| `/usr/local/bin/headscale` | 0.29.3 → 0.29.4 | `headscale.bak-v0.29.3` |
| `/etc/sing-box/bin/sing-box` | 1.13.7 → 1.14.2 | `sing-box.bak-v1.13.7` |

> sing-box 跨 minor：先以新二进制 `check -c config.json -C conf` 校验通过后才替换。

## 验证记录（2026-09-26 13:16）

- 服务全 active：frps / headscale / sing-box / fail2ban / nginx / ufw / docker / unattended-upgrades；ntfy 容器 running
- fail2ban Jail list：`nginx-bad-request, nginx-botsearch, recidive, sshd`
- sing-box 三个公网入站（45574/45575/39586）在听；frps :7000 在听；headscale 节点 brave-goose-1 已重连
- ntfy 收件箱实收 3 条：「告警通道上线」「⚠️ 每日安全摘要 09-26」「port-drift 基线初始化」
- 临时文件（/tmp/opencode/upg）已清理

## 待人工确认

- [ ] 手机 ntfy app 订阅 `https://ntfy.signal-align.com/alerts`（用户 desmond，密码见 `/root/ntfy-credentials.txt`）
- [ ] 次日 08:30 摘要到达 = 链路最终验收
- [ ] 首轮 unattended-upgrade 结果（后台执行中）；若 `/var/run/reboot-required` 出现，摘要会带 ⚠️ 提示，重启窗口自行安排

## 性能影响

新增常驻仅 ntfy 容器（~20-30MB）；脚本均为瞬时 cron。ufw 无新增公网端口（ntfy 复用 443）。

# 实施记录:ntfy 推送服务下线

执行时间: 2026-11-14 11:41–11:50 CST · 执行人: opencode 会话(desmond 确认)
回退备份: `~/Backups/ntfy-removal-2026-11-14/`(nginx vhost、cron、security-digest.sh、fail2ban 两文件、certbot 续期配置、/root 两个凭据文件、ntfy-data.tar.gz 完整数据卷)

## 执行步骤与结果

| # | 操作 | 结果 |
|---|---|---|
| 1 | 备份 8 个文件 + `~/ntfy` 数据卷 tar | ✅(含隐藏文件 .ntfy-token) |
| 2 | nginx:删软链+vhost → `nginx -t` → reload → `certbot delete ntfy.signal-align.com` | ✅ 剩余 5 张证书不受影响 |
| 3 | docker:`compose down` + `rmi binwiederhier/ntfy:v2.28.0` + 删除 `~/ntfy/` | ✅ 容器/镜像/网络/目录全清,2599 无监听 |
| 4 | cron:删 `/etc/cron.d/security-digest` + `/usr/local/bin/security-digest.sh` | ✅ |
| 5 | fail2ban:删 `action.d/ntfy.conf`,`jail.d/01-custom.local` 删除 ntfy action 行,reload | ✅ recidive jail 仍正常运行(仅不再推送) |
| 6 | 删 `/root/.ntfy-token`、`/root/ntfy-credentials.txt` | ✅ |
| 7 | Cloudflare:删除 `ntfy.signal-align.com` CNAME → bandwagon 记录 | ✅ remaining=0 |

弯路备忘:第一次 DELETE 把**记录 ID 误当 Zone ID** 用了(CF 返回 403 Authentication error,易误判为 token 权限问题)——zone 与 record 是两个不同 ID,必须分别获取。

## 最终验证

- `dig @1.1.1.1 ntfy.signal-align.com` → 空(NXDOMAIN)
- `curl https://ntfy.signal-align.com` → 000(不可达)
- `ss -tln | rg 2599` → 无监听
- certbot 剩余证书:books、derp、headscale、reading、signal-align-auth(各 vhost 80 端口续期块未动)
- fail2ban reload 后 `fail2ban-client status recidive` 正常

## 安全监控能力变化(重要)

原 2026-09-26 加固第 1 档中依赖 ntfy 的两项能力随本次下线消失:

1. **每日安全摘要心跳**(apt 可升级数/安全更新数/重启要求/fail2ban 封禁/磁盘内存)——不再产生
2. **recidive 惯犯封禁的即时通知**——封禁仍会发生(fail2ban 本身正常),只是不再推送

若日后需要恢复告警通道:备份在 `~/Backups/ntfy-removal-2026-11-14/`,或改用其他通道(邮件/Telegram/Bark)并重建订阅端。

# ntfy 推送服务下线(服务无人订阅,全量清除)

日期: 2026-11-14 · 状态: 已完成 · 实施记录: [implementation.md](implementation.md)
- 前置任务: [2026-09-26-1318-vps-security-monitoring-hardening](../2026-09-26-1318-vps-security-monitoring-hardening/)(ntfy 作为第 1 档告警通道建立)

## 背景与决策

ntfy(binwiederhier/ntfy v2.28.0,docker 容器 127.0.0.1:2599 ← nginx vhost `ntfy.signal-align.com`)为 2026-09-26 安全加固建立的告警通道。排查证据(2026-11-12/14):

- **发布者 2 个**:cron 每日 08:30 安全摘要(`/usr/local/bin/security-digest.sh` → topic `alerts`);fail2ban recidive 封禁告警(`/etc/fail2ban/action.d/ntfy.conf`,token 硬编码)
- **订阅者 0 个**:容器全量日志 67,818 条每分钟统计(2026-09-26 起 ~47 天完整历史)`subscribers` 恒为 0,重启后 48h 复查仍为 0;57+ 条通知全部发入空房间(缓存 12h 后丢弃)
- 原计划"手机端订阅"(用户本人操作)从未落地;healthcheck 路径配错(v1/health)致容器长期 unhealthy,从未有人修
- GitHub:desmondc9 全部 30 个仓库 secrets 扫描 + 本地 workflows 检索,无 ntfy 引用;systemd:无相关 unit
- 备份目录无引用

**用户决策(2026-11-14 确认)**:安全摘要 cron + fail2ban 告警**全删**(不留本地日志版);Cloudflare DNS 记录**一并删除**。

## 清除范围

1. nginx:sites-enabled/ntfy 软链 + sites-available/ntfy + `certbot delete ntfy.signal-align.com` + reload
2. docker:`ntfy` 容器 compose down + 删除镜像;删除 `~/ntfy/`(已备份)
3. cron:`/etc/cron.d/security-digest` + `/usr/local/bin/security-digest.sh`
4. fail2ban:`action.d/ntfy.conf` + `jail.d/01-custom.local` 中 ntfy action 行 + reload
5. root 凭据:`/root/.ntfy-token`、`/root/ntfy-credentials.txt`
6. DNS:Cloudflare 删除 `ntfy.signal-align.com` 记录
7. GitHub / systemd:无(已核实)

## 回退

备份:`~/Backups/ntfy-removal-2026-11-14/`(全部配置 + 凭据 + ntfy-data.tar.gz 数据卷)。恢复 = 还原文件 + compose up + certbot 重新签发 + Cloudflare 恢复记录。

## 验收标准

- [x] nginx -t 通过,`https://ntfy.signal-align.com` 不再可达(连接失败/DNS NXDOMAIN)
- [x] 127.0.0.1:2599 无监听,docker 无 ntfy 容器与镜像
- [x] cron 与脚本不存在;fail2ban reload 成功且 recidive jail 仍生效(仅去掉 ntfy action)
- [x] /root 下两个凭据文件不存在;certbot 无 ntfy 条目
- [x] Cloudflare 无 ntfy.signal-align.com 记录

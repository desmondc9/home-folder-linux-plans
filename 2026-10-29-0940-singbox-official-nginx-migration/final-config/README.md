# 最终配置快照（已脱敏，审计参考）

来源：2026-10-29已运行配置；外部Android v2rayNG验收已由用户确认。

**这些不是可直接恢复/部署的原始文件。** 认证字段已替换为占位符，JSON虽可解析但不应通过真实凭据校验。恢复需要VPS上的受限备份/真实配置，不能直接把这份快照覆盖到生产。

| 文件/目录 | 内容 |
|---|---|
| `sing-box.config.redacted.json` | 服务端完整结构；UUID/private key/short ID均脱敏 |
| `client.config.redacted.json` | CLI SOCKS客户端结构；UUID/public key/short ID均脱敏，不是Android VPN配置 |
| `client-uri.redacted.txt` | VLESS URI结构；不可直接导入 |
| `sing-box.service` | 实际local unit，含必要AF_NETLINK、非root与空capability |
| `nginx/` | 主配置、stream分流、8个活动vhost、HTTP map、stream模块与logrotate |
| `certbot/renewal/` | 7个续期profile，ACME账户标识已脱敏，证书路径仅引用 |
| `certbot/cloudflare.redacted.ini` | DNS凭据字段模板；所有真实值均脱敏 |
| `certbot/certbot-dns.cron` | 原03:00调度，reload前nginx -t |
| `symlinks.json` | 关键运行链接及sb不存在的状态 |
| `ufw-status.txt` | 最终只读规则观察，45575已删除 |
| `service-observation.txt` | 只读服务状态观察，不是永久PID/运行保证 |
| `manifest.json` | 29份配置/参考快照的源路径及脱敏后SHA256 |

公开：主机/IP/域名/端口/拓扑、文件路径、非秘密配置字段。

不公开：真实UUID、REALITY私钥/公钥及short ID、Cloudflare token/key/email、ACME账户标识、原始URI、证书/私钥PEM、原始备份及用户访问日志。公钥本身并非认证秘密，本次仍保守脱敏整个凭据bundle。

完整拓扑、排障、备份/回退注意事项与证据来源：[../final-state.md](../final-state.md)。未来auth路由更新需同步本机auth-local-edge，未来续期/部署不可把HTTP TLS listener改回公网443。

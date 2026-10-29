# 最终部署与验收记录（以本文及 final-config 为准）

- 环境：Bandwagon VPS，Ubuntu 24.04.4 LTS / linux amd64；IPv4 `104.194.83.82`、IPv6 `2607:8700:5500:7bd3::2`，主机名 `bandwagon.signal-align.com`。
- 日期：2026-10-29，时区 +08:00。
- 结果：本机迁移完成；用户随后确认 **Android 手机 v2rayNG 实测可以连接**，外部客户端验收通过。
- 发布范围：仅本机必要配置。先前错误扩大到业务仓库的 #68 已由 [#69](https://github.com/desmondc9/signal-align-umbrella/pull/69) 撤销，业务仓库内容恢复到 #68 前；没有创建 Release、执行 CD、修改应用源码/数据库或写入 Key Vault。
- 归档授权：此前用户要求记录仅本地 Git；本轮在手机验收后，用户明确授权**脱敏后完整记录到 ~/plans 并 commit/push**。该授权只涉及档案仓库，不重新授权业务仓库改动或服务发布。

## 1. 最终连接与流量拓扑

| 项目 | 实际配置 |
|---|---|
| 核心 | 官方 SagerNet sing-box **1.14.4** |
| 客户端连接地址 | `vs.signal-align.com:443` |
| 协议/传输 | VLESS / TCP / REALITY / `xtls-rprx-vision`，指纹 `chrome` |
| TLS SNI / REALITY handshake | `www.cloudflare.com` / `www.cloudflare.com:443` |
| 用户与密钥 | 新生成 UUID、X25519 配对密钥、8 bytes/16 hex short ID；与参考节点及旧安装独立，本文不记录真实值 |
| 公网入口 | Nginx stream，IPv4/IPv6 TCP 443，不终止 TLS |
| REALITY 分支 | SNI `www.cloudflare.com` → `127.0.0.1:24444` → `127.0.0.1:24443` |
| 普通 Web 分支 | 其他/未知/缺失 SNI → `127.0.0.1:14443` → 原 HTTPS vhost 与应用 |

```text
客户端 → vs.signal-align.com:443 → 本机 Nginx stream + ssl_preread
  ├─ SNI www.cloudflare.com
  │    → 24444（接受并剥离 PROXY v1）→ 24443（sing-box 原始 TLS/REALITY）
  └─ 其他 SNI
       → 14443（原 Web TLS + PROXY v1 + 仅信任回环的 real_ip）→ 原应用
```

连接域名不等于 SNI；URI 已显式设置正确的 SNI。`vs` 是代理连接地址，不承诺作为普通 HTTPS 网站打开，也不需要为它签发站点证书。

sing-box 1.14.4 已移除 PROXY protocol 输入支持，不能把 Nginx 的 PROXY 头直接发给它。因此公网 stream 对后端发送 PROXY v1：Web 直接接受它恢复原始 IPv4/IPv6 来源，REALITY 分支先经回环中继剥离它。sing-box 看到的 peer 是回环地址；真实代理来源可查公网 stream 日志。

## 2. Cloudflare DNS

操作期间通过 Cloudflare API **只读核实**以下既有记录，均 `proxied=false`，因此没有为了“完成配置”做多余 DNS 修改：

| 类型 | 名称 | 内容 |
|---|---|---|
| CNAME | `vs.signal-align.com` | `bandwagon.signal-align.com` |
| A | `bandwagon.signal-align.com` | `104.194.83.82` |
| AAAA | `bandwagon.signal-align.com` | `2607:8700:5500:7bd3::2` |

必须保持灰云/DNS-only。普通橙云 HTTP 代理不能承载这里的原生 VLESS/REALITY，不能把这次配置误当作经 Cloudflare HTTP CDN 的代理。

## 3. 官方安装、权限与旧脚本清理

- 官方文件：`sing-box-1.14.4-linux-amd64.tar.gz`。
- 来源：https://github.com/SagerNet/sing-box/releases/tag/v1.14.4
- 官方 archive SHA256：`699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968`，下载和解包前已校验。
- 核心：`/usr/local/lib/sing-box/1.14.4/sing-box`；`/usr/local/bin/sing-box` 现在指向它，不再是管理脚本入口。
- 服务：`/etc/systemd/system/sing-box.service`，已 enable；旧 vendor unit 移入受限备份，boot enable 链接指向新 local unit。
- 账户：非 root、不可登录的 `sing-box`；配置目录 `/etc/sing-box` 为 root:sing-box 0750，`config.json` 为 root:sing-box 0640。
- StateDirectory/WorkingDirectory：`/var/lib/sing-box`；NoNewPrivileges、ProtectSystem、ProtectHome、PrivateTmp/Devices；capability 集合为空，不授予 NET_ADMIN。
- `RestrictAddressFamilies` 必须含 `AF_INET AF_INET6 AF_UNIX AF_NETLINK`。
- `/etc/sing-box/sh`、旧 `conf/bin` 活动路径、`/usr/local/bin/sb` 不再存在；原安装在备份内保留，未执行范围过宽的 233boy uninstall。
- 旧入站 45574/45575/39586 停止监听，45575 的 IPv4/IPv6 UFW 放行已定向删除；没有新增内部端口的公网放行。
- 临时服务、SOCKS 验证端口、运行时凭据副本、测试容器/API/测试镜像已收尾；没有安装通用发布/watchdog 框架。

## 4. 既有 Nginx 应用与维护边界

11 个原 HTTPS 名称：auth/identity/login/bandwagon/headscale/derp/ntfy.signal-align.com，以及 books-and-articles/api.books-and-articles/reading-app/api.reading-app.desmondchen.com。

这些 vhost 的 TLS 监听移到 `127.0.0.1:14443 ssl http2 proxy_protocol`；仅信任 127.0.0.1 的 PROXY 来源。HTTP 80、原 upstream/root/location/header、证书路径保持；Web/DERP/Headscale 长连接超时不缩短。独立 18790 的 OpenClaw TLS 配置不增加 PROXY/real_ip，证书未变，应用进程/容器没有重启；共享 Nginx 重启期间连接可能重连，已提前获用户许可。

所有内部 Web TLS server 增加 `port_in_redirect off`，防止 Nginx 自动目录跳转泄露内部 `:14443`。reading/books `/assets` 的 Location 已验证为正常外部 HTTPS 地址，实际静态资源 HTTP200。

**auth 的本机覆盖必须保留：**

- `/etc/nginx/sites-enabled/auth` → `../sites-available/auth-local-edge`。
- 原 `/home/desmond/signal-align-auth/nginx-auth.conf` 内容 SHA 与迁移前相同，没有编辑部署目录或业务仓库文件。
- 以后 auth 路由/upstream 发生变化，需人工同步本机副本；不能假设应用 CD 推送的旧文件会自动更新该本机入口。
- 未来任何安装器/配置更新都不能把这些 Web vhost 直接改回公网 443，否则会与 stream 争抢端口。

## 5. 证书续期兼容

- 已有 `/opt/certbot-dns/bin/certbot` 为 5.8.0，含 DNS Cloudflare 插件；系统旧 Certbot 2.9.0 不含该插件。
- bandwagon/derp/headscale 三个 lineage 通过官方 `reconfigure` 内置的真实 DNS-01 staging 验证，分别耗时39.3/38.8/39.6秒，保存为 dns-cloudflare + null installer；不是生产强制重签。
- 使用 `--no-directory-hooks`，未传 `--run-deploy-hooks`，活跃证书文件与 derper PID 均未变化。
- 最终7个 renewal profile 都使用 DNS，没有 nginx installer；原域名/SAN/证书路径不变。
- 续期只保留原 `/etc/cron.d/certbot-dns` 的每日03:00任务，deploy hook 在 nginx -t 成功后 reload；系统 certbot.timer 已 disable/inactive。旧系统 cron 有 systemd guard，在本机不会执行。
- 原 derper 证书复制 hook 保持不变，实际生产续期时仍按原逻辑处理；dry-run 不应触发它。
- DNS 凭据真实文件为 `/etc/letsencrypt/cloudflare.ini`（root 0600），归档仅有脱敏模板，不包含真实 token/key/email。

## 6. 原始备份与回退

- 根目录：`/var/backups/sing-box-migration/2026-10-29-111755-local/`，root 0700。
- 原始包：`original.tar.gz`，root 0600。
- SHA256：`b0b2d9d2a32535020a38971a27bba01365a107ebac3f9c72f2167fdeb2a0a6a3`。
- 包含旧核心/脚本/配置/service/链接、Nginx、auth 外部链接目标、LE 证书与DNS凭据、原调度及UFW规则；已试解包，核验关键内容、UID/GID、mode及symlink。
- 原始包、`state.json`、`legacy-live`、旧vendor unit、失败尝试的新配置和本机私有日志都留在 root 受限目录；不上传 Git，至少保留30天。

回退前须重新检查是否有后续人工修改，不可盲目覆盖。原 archive 不包含后来创建的 local unit：需要先保留新配置并移除 `/etc/systemd/system/sing-box.service` 的新 override，再恢复旧 core/config、vendor unit、CLI链接和Nginx布局，daemon-reload、reenable旧unit；仅按需加回45575，不覆盖整张后来变更过的防火墙。DNS续期兼容旧Web布局，不必恢复旧系统Certbot timer。

这些是恢复注意事项，不是要求现在执行的命令；本次已真实执行过一次回退并恢复全部原站点。

## 7. 排障与切换证据

1. 初次预览未应用完整正式 sandbox，直接代理成功，但首次正式启动因本人遗漏 AF_NETLINK 而失败：`initialize network: create netlink socket: address family not supported by protocol`。
2. 新代理检查失败后自动回退，切换与恢复共15.44秒；随后逐一核实11个原站点恢复。没有连续盲目试切。
3. 用户授权最小修正后，补 AF_NETLINK，不增加 capability；先以完整正式属性预览，验证实际监听/代理和零重启，再切正式入口。不能只凭启动瞬间的 `is-active` 判断进程已稳定监听。
4. 成功轮总操作9.14秒，Nginx重启5.17秒；正式代理经 IPv4、IPv6、vs 域名分别 HTTP200，主服务 NRestarts=0。
5. 后续发现静态目录跳转带14443，经用户确认补 `port_in_redirect off` 并平滑reload，master PID不变；复测正常。reload/Type=exec 返回并不保证新worker/应用监听在同一瞬间就绪，探测应有有界就绪检查。

## 8. 最终验收与证据来源

| 检查 | 结果/来源 |
|---|---|
| 官方版本、非root用户、零capability、开机启用 | 本机命令验证，1.14.4 / sing-box / enabled |
| 正式443 REALITY vision代理 | 本机分别连接127.0.0.1、::1、vs域名，HTTPS目标HTTP200 |
| 最终私有client.json | 以desmond账户运行验证，vs:443代理HTTP200，测试单元随后停止 |
| 原11域 | IPv4/IPv6 root状态、跳转、CA验证与原证书fingerprint一致 |
| 原7个health | IPv4/IPv6 HTTP200 |
| 来源地址 | 实测经过IPv4内部回环后，Web日志仍记录正确IPv4/IPv6客户端来源 |
| 静态目录/资源 | reading/books无内部端口跳转，静态资源HTTP200 |
| 独立18790 | 原TLS证书fingerprint不变；未重启OpenClaw |
| 旧脚本/端口/防火墙 | 活动路径移除，旧端口不监听，45575规则已删除 |
| **Android v2rayNG 外部实机** | **用户于本轮对话确认“实测可以连接”**，不是代理自证的本机回环测试 |

用户未提供 v2rayNG 版本、运营商、网络类型或实际IP族，因此不虚构“手机单独验证了公网IPv6”，也不宣称完成吞吐压测、所有业务E2E或长期稳定性验证。

## 9. 私有客户端交付

真实文件（0600，目录0700）：

`~/.config/sing-box-client/vs.signal-align.com/2026-10-29-111755-local/client-uri.txt`

同目录的 `client.json` 是本机CLI SOCKS参考配置，不是Android的VPN/TUN配置。Android v2rayNG 已通过URI导入并实测。归档中的URI/JSON仅保留结构和脱敏占位符，不能直接导入或运行；更换真实凭据时需同步服务端、客户端与URI，不再使用233boy管理命令。

## 10. 运维检查（只读）

```bash
sing-box version
sudo systemctl status sing-box nginx --no-pager
sudo nginx -t
sudo ss -lntp
sudo journalctl -u sing-box --since '10 minutes ago' --no-pager
```

stream日志：`/var/log/nginx/stream-access.log`；日志权限与既有access.log一致，沿用 `/var/log/nginx/*.log` 的daily/14份轮转。日志可能含用户IP/目标信息，不能不加检查就上传。

## 11. 配置归档与容量边界

完整配置引用见 [final-config/README.md](./final-config/README.md)，每份导出文件的来源及**脱敏后文件**SHA256见 [manifest.json](./final-config/manifest.json)。没有复制证书、私钥PEM、二进制、原始备份、未脱敏客户端文件或原始日志。

本次触发网关/外部调用/续期调度门禁，无DB/cache/业务应用变更。保留原6 worker/768 connections配置，完整连接约4个Nginx slots；未压测，不把理论连接预算当成额定吞吐。stream preread10s、connect3s、idle24h；core目标connect5s、TLS握手15s，既有Web长连接超时保留。没有新增长期运行的管理服务或周期任务；VM本身仍是单机故障域。

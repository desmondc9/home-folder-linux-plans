# nginx 配置审查（http2 迁移后全量复查）

- 环境: Bandwagon VPS，nginx/1.28.3 (Ubuntu)；入口 = 公网 443 → stream SNI 预读（`stream-enabled/sing-box-443.conf`，`www.cloudflare.com`→sing-box 24443，default→127.0.0.1:14443 proxy_protocol）→ http vhost；80 直接 http。
- 日期: 2026-11-14
- 状态: 审查完成；**未做任何变更**（修复建议待用户决定）
- 起因: 用户问 http2 on; 是否影响 HTTP/1.1（不影响，见下）并要求全量检查

## Q: `http2 on;` 影响 HTTP/1.1 吗？

**不影响**。该指令只开启 TLS 层 ALPN 里的 h2 协商；客户端不在 ALPN 里提供 h2（或明文 :80）时按 HTTP/1.1 服务。实测（2026-11-14）：`curl --http1.1` 对 auth/derp/headscale/rakazo 全部正常（200/307/405），同一批站 `--http2` 协商 h2——两协议并存。

## 发现（按严重度）

### A（中）TLS 协议下限：7 个 server 块继承含 TLSv1/1.1 的全局默认
- `nginx.conf` http 级 `ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;`（发行版陈年默认，注释还写着 POODLE 时代的话）
- 仅 derp/headscale/rakazo 的 server 块 include 了 certbot `options-ssl-nginx.conf`（TLSv1.2+1.3）；**auth-local-edge×3、books×2、reading×2 未 include** → 继承全局默认，配置面上接受 TLS 1.0/1.1（本机 openssl 3 无法本地复现握手，按配置判定）
- 修复建议（一处改动全覆盖）：nginx.conf 全局改 `ssl_protocols TLSv1.2 TLSv1.3;`，顺带 `ssl_prefer_server_ciphers off;`（TLS1.3 下的现代默认；certbot options 在 3 个 vhost 已是 off，改全局只是拉齐）

### B（低）`server_tokens` 未关
- 响应头暴露 `Server: nginx/1.28.3 (Ubuntu)`（实测可见）。建议 http 级 `server_tokens off;`

### C（低/卫生）14443 无显式 default_server
- 未知 SNI 经 stream default 落到 14443 后命中**字母序第一**的 server 块（auth-local-edge）→ 返回错误证书（重启 rakazo 前实测到 "no alternative certificate subject name matches"）；:80 同理落 auth 的 301
- 建议：加显式 `default_server` 块（listen 14443 ssl proxy_protocol + 自签/任意证书 + `return 444;`）与 :80 default_server 444，吞掉未知 Host/SNI

### D（卫生）websocket map 重复定义
- `conf.d/headscale-map.conf` 已有全局 `map $http_upgrade $connection_upgrade`（derp/headscale 在用）；rakazo.conf 内又定义了一份（2026-11-12 引入，当时未查全局）。nginx 1.28.3 对相同参数的重复 map 容忍（多轮 nginx -t 通过，行为正确），但属冗余——建议 rakazo.conf 删除本地 map（走 repo PR + host-setup 重装）

### E（事实修正，非问题）ntfy / headscale-new vhost 已于 11-14 12:00 整体删除
- sites-available 与 sites-enabled 均已无这两个文件。本档案 http2 条目曾写「ntfy/headscale-new 已是新写法未动」**有误**，已更正为「已被删除」

### F（备忘小项，不建议现在动）
- `worker_connections 768`：发行版默认偏低，当前流量够用
- 无 OCSP stapling、无 HSTS：可选优化，按服务逐个决定（HSTS 对 API 域名族有粘性风险）
- certbot 三件套 include 只覆盖 derp/headscale/rakazo；auth/books/reading 连 dhparam 也没挂——A 的全局修复会覆盖协议面，dhparam 只影响 TLS1.2 DHE 套件，可忽略

## 验证方法备忘
- 直连 `127.0.0.1:14443` 测 TLS 不可靠：listener 带 proxy_protocol，无 PROXY 头握手即失败（Cipher is (NONE)）；协议测试须走公网 443 或 stream 路径
- 本机 openssl 3 无法强制 TLS1.0（客户端 MinProtocol 限制），协议下限问题只能配置面判定

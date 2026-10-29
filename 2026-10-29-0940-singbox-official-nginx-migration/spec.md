# sing-box 官方版本迁移：需求与只读调查

- 环境：Bandwagon VPS，本机 Ubuntu 24.04.4 LTS / linux amd64；IPv4 `104.194.83.82`，IPv6 `2607:8700:5500:7bd3::2`；主机域名 `bandwagon.signal-align.com`。
- 调查时间：2026-10-29 09:40–09:41 +08:00。
- 状态：仅完成初步只读调查；方案未选择、设计未批准，未开始备份、安装、卸载、DNS 修改或服务切换。

## 用户目标

1. 完整备份 233boy/sing-box 安装的服务，随后移除其管理脚本。
2. 使用 SagerNet/sing-box 官方 1.14.4，保留参考节点的 VLESS / TCP / REALITY / `xtls-rprx-vision` 组合；客户端指纹参考 chrome。不得复用参考节点的用户标识、密钥或 short ID。
3. 由 Nginx stream + ssl_preread 接管公网双栈 TCP 443，sing-box 位于回环地址；保护既有 HTTPS 应用。
4. 客户端使用 `vs.signal-align.com:443`；Cloudflare DNS 由用户控制。
5. 文档用 Git 归档到 `~/plans`；秘密和原始备份不得进入公开仓库。

## 已确认现状

- 当前 sing-box **1.14.2**，进程使用 `/etc/sing-box/bin/sing-box run -c /etc/sing-box/config.json -C /etc/sing-box/conf`；service 为 `/usr/lib/systemd/system/sing-box.service`，root 运行。
- `/usr/local/bin/sing-box` 是指向 `/etc/sing-box/sh/sing-box.sh` 的管理脚本链接，不是核心二进制。卸载必须区分脚本、核心、配置和 service；不能直接执行未经审查的第三方卸载流程。
- 三个入站：45575 VLESS REALITY vision（www.ebay.com）、45574 VLESS HTTP2 REALITY（aws.amazon.com）、39586 VLESS REALITY vision（www.cloudflare.com）。本次只输出配置结构，未输出认证值。
- 公网 TCP 443 已由 Nginx 的 HTTP TLS 虚拟主机占用；尚无活动 stream 443 分流。
- Nginx 1.24.0，已编译 ssl_preread；stream 动态模块已加载，模块链接修改时间为本日 **09:22**，早于本次操作，应确认是否存在并发配置工作。
- 既有 HTTPS 名称：auth/identity/login/bandwagon/headscale/derp/ntfy.signal-align.com，以及 books-and-articles/api.books-and-articles/reading-app/api.reading-app.desmondchen.com。OpenClaw tailnet TLS 为独立 18790，应保持不变。
- auth 的 Nginx 配置链接到 `/home/desmond/signal-align-auth/nginx-auth.conf`，不能忽视其源码归属和后续部署覆盖风险。
- `nginx -T` 通过，但部分 443 listen 的协议选项不一致产生警告；不是语法失败。
- UFW 默认拒绝入站，443 已对双栈放行；旧 sing-box 仅 45575 有明确放行，39586/45574 没有对应规则。该事实可能解释部分节点不可达，但**不能据此断言用户当前故障的完整根因**；未从用户客户端网络完成复现。
- `vs.signal-align.com` 当前 DNS 查询显示 CNAME 到 `bandwagon.signal-align.com`，最终解析到上述 A/AAAA；尚未调用 Cloudflare API 确认记录及代理状态，因此不能声称已经修改或完全验证 DNS。
- 通过已认证 `gh api` 核实官方 latest 为 **v1.14.4**，发布时间 2026-10-24T01:04:25Z，存在 linux amd64 官方 deb/tar 包。未认证 GitHub API 被本机共享 IP 的速率限制拒绝，不能将其误判为版本不存在。

## 必须先解决的设计约束

- 客户端连接域名与 REALITY SNI 是两回事。Nginx ssl_preread 读取 ClientHello SNI，无法根据用户填写的连接地址分流。
- Cloudflare 普通橙云 HTTP 代理不能承载这里的原生 VLESS/REALITY；应使用 DNS-only。DNS 管理凭据只引用本机文件路径，不在文档或输出中打印。
- 外部 REALITY 握手目标必须独立验证可达性、TLS 能力与客户端兼容性，不能盲目继承参考节点的第三方站点。
- 自有域名作为 REALITY SNI 需要匹配实际握手目标和证书；不能只将第三方 SNI 字符串替换成 vs 域名。
- 所有现有 HTTP 层 443 监听需要迁移到内部 TLS 监听，再由 stream 默认路由保持证书与应用行为；需覆盖 IPv4/IPv6、HTTP/2、WebSocket、DERP、回调和证书续期行为。
- stream 会改变 HTTP 后端看到的源地址。设计必须明确真实 IP 保留方案及仅信任回环的边界，不能无意破坏鉴权、审计或限流，也不能给不支持 PROXY protocol 的 REALITY 入站加此前缀。
- 生产服务禁止带外热改的纪律仍适用：调查配置所属仓库和发布入口，先批准版本化部署路径；不改 LibreChat、signal-align 相关运行目录或重启 OpenClaw。
- 备份应位于 Git 仓库外，包含旧核心、脚本、配置、unit/drop-in、Nginx 配置及链接目标、必要证书引用和防火墙状态；目录限制访问，校验可恢复后才清理旧安装。

## 待用户选择

推荐保持外部站点作 REALITY SNI/握手目标，连接地址使用 vs；另一种是以自有 vs 域名和自有 TLS 站点作目标，代价是新增证书和站点维护。两种均可使用 stream 分流，前者更接近用户给定协议参考。尚未确定选项，本文不是获批的最终设计。

## 验收草案

- 官方核心报告 1.14.4，新配置检查成功，认证值全部新生成且不入库。
- sing-box 仅回环监听；公网双栈 443 由 stream 接管；其他既有业务和独立端口保持行为。
- VLESS vision 客户端经真实公网入口完成代理请求；分别检查 IPv4/IPv6，并区分本机回环测试与用户网络验收。
- 各既有 HTTPS 名称迁移前后证书、状态码和必要长连接行为对比；续期配置不回写公网 HTTP 443。
- vs DNS-only 解析正确；输出私有客户端配置文件路径，公开档案只放脱敏模板。
- 原始备份可恢复；233boy 管理脚本、入口和相关自动任务清理有准确范围和记录。

## 性能与容量

本次只读调查未改变运行路径；后续迁移触发网关/外部调用性能门禁。需在最终设计记录 stream 连接预算、文件描述符上限、握手/上游连接/空闲超时、长连接行为、源 IP 信任边界及日志轮转。尚未采集业务流量基线，不做未经验证的吞吐承诺。

## 参考

- https://github.com/233boy/sing-box
- https://github.com/SagerNet/sing-box/releases/tag/v1.14.4
- https://sing-box.sagernet.org/configuration/shared/tls/
- https://nginx.org/en/docs/stream/ngx_stream_ssl_preread_module.html

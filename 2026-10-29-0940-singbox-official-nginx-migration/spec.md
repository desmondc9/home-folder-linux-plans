# sing-box 官方版本迁移：需求与只读调查

- 环境：Bandwagon VPS，本机 Ubuntu 24.04.4 LTS / linux amd64；IPv4 `104.194.83.82`，IPv6 `2607:8700:5500:7bd3::2`；主机域名 `bandwagon.signal-align.com`。
- 调查时间：2026-10-29 09:40–09:41 +08:00。
- 状态：用户选择方案 A、了解 host-only CD 范围并选择 Native；阶段1候选实现已提交PR #68、CI通过，等待合并确认。未开始生产备份、安装、卸载、DNS修改或服务切换；切换前仍须核对并发作业与维护时机。
- 跟踪：signal-align-umbrella [#67](https://github.com/desmondc9/signal-align-umbrella/issues/67)。

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

## 方案选择与边界

用户回复「A, 继续」，选择外部站点作 REALITY SNI/握手目标，连接地址使用 vs。备选 B（自有 vs 域名同时作 SNI）增加站点和证书维护，因此未选。单独使用其他公网端口不能满足共享 443 的要求；普通 Cloudflare 橙云也不能承载此原生协议。

这是涉及共享入口与发布链的系统迁移，不是一个只改 sing-box JSON 的小任务。最终实施应拆成可独立验证的小阶段；本文件是设计，不是已执行的详细计划。

不在范围内：重装 OpenClaw、修改 LibreChat 配置、升级 auth 应用、迁移数据库、增加 VPN/TUN/透明路由、改变 80/18789/18790/8443 等现有服务端口、承诺绕过某网络的封锁。外部 SNI 不是鉴权机制，安全性依赖新的 REALITY 密钥及 VLESS 用户凭据。

## 补充取证（09:47–09:52 +08:00）

- Cloudflare GET API 确认：`vs.signal-align.com` 为 DNS-only CNAME → `bandwagon.signal-align.com`；后者 A/AAAA 均 DNS-only 且地址正确。**保留现状，不进行无意义的 DNS 写入**。凭据仅在进程内读取 `~/.cloudflare/credentials.jsonc`，未打印真实值。
- 外部目标测试：`www.cloudflare.com` 经 IPv4/IPv6 均返回 HTTP/2 200，TLS 1.3 与主机名校验通过；推荐此目标。`www.microsoft.com` 的 IPv4 HTTP 探测 10 秒超时而 IPv6 正常，因此不选。参考域名虽可握手，不作为本次默认目标。
- 7 个证书 lineage 中，auth/books/reading/ntfy 已采用 DNS Cloudflare；bandwagon/derp/headscale 仍采用 nginx authenticator + installer。
- 本机有两套 Certbot：系统 2.9.0 不含 DNS Cloudflare；`/opt/certbot-dns` 为 5.8.0 且有 DNS Cloudflare 插件。03:00 的 `/etc/cron.d/certbot-dns` 使用后者；同时存在系统 timer。迁移后应统一使用已有 DNS 专用版本，防止双调度与插件缺失。
- derper 的现有全局 deploy hook 会复制证书并重启 derper；不能为了测试而使用 `--run-deploy-hooks`，也不能把无关证书重新签发当作普通只读动作。
- auth 配置与 `signal-align-umbrella/local/vps/nginx-auth.conf` 的 SHA256 完全相同；其发布脚本每次 scp 覆盖该文件，但仅首次创建链接时 reload。该发布行为必须同步修正，不能仅改线上文件。
- fetch 后发现 umbrella 本地 checkout 过旧，设计以 **origin/main 44a084d** 为准，未 pull/覆盖旧 checkout。它没有 `.gitmodules`，是单仓库 shape A，不因名字叫 umbrella 就按 submodule 流程操作。
- 最新源码及 Azure 查询确认实际 Vault 为 **signal-align-kv-w2 / westus2**；旧 `signal-align-kv` 不存在。当前 Azure 登录为 service principal，能够读取 Vault 与 secret 名称；尚未执行任何 Vault 写入，也不预先声称具有写权限。全局文档提到的本机 SP 凭据文件在此 VPS 不存在，无需向用户索要现有 token。
- 最新通用 auth CD 仍有引用旧 Vault 的迁移步骤。该既有问题不顺手重构；本次选择独立的 host-only 发布分支，避免触发 auth 重建/数据库迁移，详见发布设计。

## 目标拓扑与协议契约

公网 IPv4/IPv6 TCP 443 由同一 Nginx stream 入口承接，不做 TLS 终止：

- SNI 精确为 `www.cloudflare.com` → `127.0.0.1:24444`（Nginx PROXY 解包中继）→ `127.0.0.1:24443`（sing-box REALITY）。
- 其他 SNI、未知或缺失 SNI → `127.0.0.1:14443`（原 Nginx HTTP TLS 虚拟主机集合，保持既有默认站点与证书选择）。
- 客户端连接 `vs.signal-align.com:443`，但 SNI 填 `www.cloudflare.com`，不是 vs。客户端保留 VLESS / TCP / encryption=none / flow=xtls-rprx-vision / REALITY / chrome 指纹；不加 HTTP2 transport，不套 WebSocket。
- sing-box REALITY handshake 指向 `www.cloudflare.com:443`。服务器生成新的 X25519 密钥对、新 UUID 和随机 short ID。不得复用参考或旧入站凭据；short ID 长度和字段通过 1.14.4 核心校验与往返测试固定。
- 不为 vs 签发 HTTPS 证书；它在本方案是连接地址，不是 Web 服务承诺。用浏览器打开 vs 是否有匹配证书，不作为代理健康判据。
- REALITY 自身鉴权失败的握手按核心的目标转发语义处理；不得让它回到本机公网 443 形成环路。

### 保留 Web 真实客户端地址

官方 1.14.4 的 `option/inbound.go` 明确把 proxy_protocol 标记为 removed，不能给 sing-box 配一个假想的 PROXY 支持开关。

设计：公网 stream server 使用 `proxy_protocol on`，向两类内部目标发送 PROXY v1。HTTP TLS 监听 `127.0.0.1:14443 ssl http2 proxy_protocol`；各迁移的 TLS server 中仅信任 `127.0.0.1`，用 `real_ip_header proxy_protocol` 恢复源地址，既有 X-Forwarded-For/日志/限流沿用恢复后的 `$remote_addr`。不在 http 全局改 real_ip，避免影响 80 和独立 18790。

REALITY 分支先进入仅回环的 24444 stream server：其 listen 接受 PROXY，转发到 sing-box 时明确关闭 PROXY。sing-box 只收到原始 TLS；其 peer 显示为回环是已知限制，客户端真实来源记录在公网 stream 连接日志。不能用透明绑定/内核策略路由来绕过此限制。

三项新增内部端口目前均空闲；不对外发布、不增加 UFW 放行规则。外部攻击者不能直接注入内部 PROXY 头，公网 443 自身不接受 PROXY 输入。普通本机进程能连接回环是现有主机信任边界，迁移不声称隔离恶意本机用户。

## 官方核心安装与权限

采用官方 release tarball（而非第三方安装脚本，也不执行 curl|bash）：

- 文件：`sing-box-1.14.4-linux-amd64.tar.gz`，官方 asset 记录大小 31,710,753 字节。
- 官方 asset digest：`sha256:699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968`，来源为认证 GitHub release API；执行时下载后再次校验。
- 核心版本目录：`/usr/local/lib/sing-box/1.14.4/`；`/usr/local/bin/sing-box` 最终链接到官方核心，不再指向管理脚本。
- 配置：`/etc/sing-box/config.json`，仅一个新入站，不再加载旧 conf 目录；root 管理，专用非登录 sing-box 用户只读，文件 0640、目录 0750，客户端私有文件与备份 0600/0700。
- systemd 使用 `/etc/systemd/system/sing-box.service`，非 root 用户运行，显式指向官方核心和新配置；无 TUN/低端口要求，不授予 NET_ADMIN 或 BIND_SERVICE。设置 NoNewPrivileges、ProtectSystem、ProtectHome、PrivateTmp 与明确可写状态目录；启动前执行配置检查。
- 精确删除已备份的旧 `/usr/local/bin/sb` 链接及 `/etc/sing-box/sh` 管理脚本；旧核心、旧 conf 和手工 vendor unit 在新服务接管后从活动路径清理到受限备份。**不执行 233boy uninstall**：已审查到它会递归删整个核心目录、service，并按名字删除 `/root/.bashrc` 的行，范围过宽。
- 不执行 autoremove，不触碰 caddy 或其他服务；旧 45575 的双栈 UFW 放行只在迁移验收后定向移除，不改变默认策略。

## 机密来源和交付

遵守现有发布纪律：新 UUID、REALITY 私钥、short ID 通过 `signal-align-kv-w2` 的新命名条目管理，public key 与其配套；用安全生成流程获取后通过不回显 stdin/file 输入 Vault，记录版本 ID 而非值。CI 以 production OIDC 身份读取并掩码，使用新独立 renderer 渲染 sing-box 配置，不混进 auth `.env`，不作为 artifact/cache 上传。

Tofu secret 清单和输出同步新增独立 edge 消费契约；不为 sing-box 创建 ACA app，不修改 auth 应用镜像或数据库。值不经过命令行输出和 PR，private key 不写进公开 plans。本机 Azure 写权限或 CI Vault 读取权限不足时停止并报告，不扩大权限、不索要或输出已有凭据。

私有交付：`~/.config/sing-box-client/vs.signal-align.com/`，目录 0700，客户端 JSON 与 VLESS URI 文件 0600、归 desmond 所有；公网档案只放占位符和文件路径。客户端不需要服务器私钥。后续 release 默认读已存在的 Vault 版本，不每次自动轮换凭据。

## 生产配置源码与发布路径

在 **signal-align-umbrella**（private、最新 main）内，用一个关联 GitHub issue 的任务分支/worktree 承载源码和测试；`~/plans` 仅作公开脱敏设计/操作档案，遵循该档案库直接 main commit/push 的特例。不得在旧 checkout 或 `~/signal-align-auth` 直接编辑生产配置。

新增 VPS-edge 部署范围，复用该 repo 的已有 Release → GitHub Actions + OIDC/Tofu/SSH 凭据，**不运行 auth 的 build、compose up 或数据库 migrate**：

- release notes 的独立完整行 `deployment-target: vps-edge` 选择本次 host-only 范围；通用 CD 的 resolve 根据同一个严格解析器分流。未带该行的发布保留原 full 行为；未知/重复/矛盾 selector 拒绝，不静默降级。
- host-only 作业固定 checkout 被发布的 tag，environment=production；读取现有 image_tags 原样传入 Tofu，plan/apply 禁止变更 auth 的随机 secrets、镜像或其他无关资源。release 命名 `vYYYY.MM.DD[-N]`。执行前必须人工可读地核验 plan；非本任务资源变更阻断。
- 同一入口执行 KV 引用/元数据 apply → 独立配置渲染 → SSH/scp staging → 预检 → 备份 → 激活 → 健康探测 → 失败恢复。CD 与普通 auth deploy 共享主机部署互斥锁，不能并发覆盖 auth vhost。
- `local/vps/nginx-auth.conf` 在源码内迁到内部监听，正常 auth CD 以后也只能部署这个布局。修正 deploy-vps 对已存在 auth 链接只覆盖不验证/reload 的行为，保证正常后续发版不打回公网 HTTP 443。
- 其他当前人工维护的 vhost/nginx.conf/renewal profiles 由新 host deployment 统一承接：只导入当前完整配置的脱敏模板，秘密只保留路径引用；保持路由、root、headers、location、默认站点顺序。对每个文件采用预期原始哈希/目标哈希检查；不认识的变化停止，不覆盖本次调查后的人工作业。
- 此次现有站点都归同一个仓库的一次共享入口变更。其他 app 仓库无须提交；不把本任务变成跨仓库功能或 auth 应用升级。

这里新增发布分流能力是避免带外热改和无关应用重启的必要范围。已向用户解释它属于额外范围；用户随后回复「好的, 继续」，据此进入实施规划，不据此声称 pipeline 已修改或服务已部署。

## 证书续期设计

复用已有 `/opt/certbot-dns` 和 `/etc/letsencrypt/cloudflare.ini`（0600 root，不导出值），把 bandwagon/derp/headscale 三个 lineage 从 nginx 插件迁到 DNS Cloudflare，无 Nginx installer；所有既有证书路径/域名/SAN 不变。使用 Certbot 支持的 reconfigure 工作流并在实施前固定命令参数，确实不能去除旧 installer 则阻断，不直接假设 migration 成功。

保留 03:00 DNS 专用 cron 为唯一续期调度，受控停用系统 Certbot timer 与其旧 cron 的重复入口，调度变更也由 CD 完成。Nginx reload hook 先 nginx -t；保留原 derper cert-copy hook，但只在实际获批续期/新证书激活时执行。dry-run 不启用 deploy hooks，避免重启 derper；不要求生产环境立即重签所有证书。

续期 dry-run 是显式部署验收步骤，不属于前期只读调查。若需要变更外部 Cloudflare DNS challenge 记录，只允许 Certbot 对 `_acme-challenge` 的必要瞬时操作，失败应清理，不改业务记录。

## 备份、激活、失败恢复

备份位置：`/var/backups/sing-box-migration/<deployment-timestamp>/`（root 0700、备份文件 0600、仓库外）。备份包含完整 `/etc/sing-box`、旧两个命令链接、unit/drop-in/enable 状态、Nginx 全树及 auth 链接目标内容、完整 Let’s Encrypt 状态与续期调度、UFW 状态/用户规则、服务版本和文件校验清单。原始压缩包不传 GitHub artifact；在受限目录试解包并校验关键文件/链接/权限，未通过则不卸载任何内容。保留至少 30 天，不能在收尾自动删除。

切换设计：先 staging 新核心/配置并在独立回环测试服务验证（不抢现有 sing-box service）；再预检候选 Nginx 配置，受主机锁保护地备份和切换。公网 listen 从 HTTP 移交 stream 是相同 socket 的处理器切换，**不能承诺一次 reload 零中断**；本次明确使用 CD 内受控 stop/start 激活，包含独立 18790 的 Nginx 长连接也可能重连，应用容器及 OpenClaw 不重启。

暂定维护窗口 **2 分钟总恢复预算**，包含激活、关键健康检查和必要的回滚恢复，而不是失败后再额外等待两分钟。分配：T0 停止旧 Nginx 并开始切换；T+30s 前目标是新 sing-box/Nginx active；T+60s 前必须通过恢复关键探测，否则进入回滚，T+120s 前恢复旧服务并验证。正常目标为数秒，但不能保证系统故障时一定 120s 内恢复；超时视为事故并立即报告，绝不自动扩大维护窗口或连续试错。

窗口内恢复关键探测限于：服务 active/正确监听、所有 Web 证书和基线响应的并行限时检查、auth/identity/login 三个专门健康端点、通过公网地址/新 443 处理链的本机 REALITY 代理请求，以及独立 18790 的原行为。每轮探测统一总 deadline，不能 11 个站点逐个重试把预算耗尽。SSH 22 不在变更范围，恢复控制通道不依赖 443；自动恢复由 CD 下发的受审计事务处理器与本机限时 watchdog 执行，不依赖 Actions/SSH 会话持续存活，也不在聊天中临时手工修生产。

备份/试恢复、官方包校验、回环候选配置测试、证书 DNS reconfigure 和无 deploy hook 的 dry-run 都在 T0 前完成，任何失败都不进入维护窗口。GitHub runner 外网探测与用户所在网络的客户端验证在窗口后执行；可达的公网双栈探测失败仍属于需恢复/修复的验收失败，但不能让等待用户操作阻塞自动恢复定时器。没有可用外部 IPv6 探测源时明确标为「外网 IPv6 待验收」，不声称完全可用。

旧脚本可在校验备份后移出活动路径（先于新服务接管）；旧核心/配置只作为受限备份保留，不在正式路径混用。**本设计不并行保留旧节点**：同一个 sing-box service 接管时，45575/45574/39586 旧入站立即停止，旧客户端必须换新配置；这是提请批准的迁移影响，不是承诺旧节点一直在线。窗口内健康检查通过后才删除活动路径中的旧残留和定向移除旧 UFW 45575 放行；在外部客户端验收完成前保留全部可恢复备份，任务状态为「已部署、待外部验收」，不标全部完成。失败恢复对认证值必须引用当次原始备份/原 Vault 版本，不随机生成旧值。

## 验收草案

- 官方核心报告 1.14.4，新配置检查成功，认证值全部新生成且不入库。
- sing-box 仅回环监听；公网双栈 443 由 stream 接管；其他既有业务和独立端口保持行为。
- VLESS vision 客户端经真实公网入口完成代理请求；分别检查 IPv4/IPv6，并区分本机回环测试与用户网络验收。
- 各既有 HTTPS 名称迁移前后证书、状态码和必要长连接行为对比；续期配置不回写公网 HTTP 443。
- vs DNS-only 解析正确；输出私有客户端配置文件路径，公开档案只放脱敏模板。
- 原始备份可恢复；233boy 管理脚本、入口和相关自动任务清理有准确范围和记录。

## 性能与容量

本轮仅设计；部署会触发网关/外部调用/续期调度门禁。基线来自本机生产读数（2026-10-29）：6 vCPU、约 8004 MiB RAM、可用约 6314 MiB，load 0.02/0.08/0.08；Nginx worker_processes auto（6）、worker_connections **768/worker**，service LimitNOFILE 524288；sing-box 旧 LimitNOFILE 1048576、常驻约 74 MB。三个新增回环端口空闲，观测时 Nginx established socket 4 个。

未发现运行的 Prometheus/Grafana 等监控 unit；从现有 Nginx access.log 及 14 个轮转文件聚合：最近 24h 2338 请求、峰值 206 请求/分钟；请求的 30d 窗口实际只有 **10-15 至 10-29** 可用数据，42309 请求、峰值 1164/分钟。现有日志无 request_time，不能声称掌握 p95/p99，也不能以 HTTP RPS 推导隧道流量或并发。

设计上把 worker_connections 调到 **4096**、显式 worker_rlimit_nofile **16384**，不提升现有 systemd 上限。Web 连接经过 stream、HTTP TLS 及可能的 app proxy，在 Nginx 内保守按 4 个 connection slot 预算；REALITY 经过两层 stream，约 4 个 slot，另有 sing-box 的入/出站 FD。六 worker 理论 aggregate 约 6144 条完整链路，**不是压测保证**，留至少 50% 余量且考虑 worker 分布和其他端口。验收阶段不对共享生产入口做高压负载测试。

超时初值：公网 preread **10s**；回环 proxy connect **3s**；REALITY 目标 connect **5s**，TLS handshake **15s**；stream inactivity **24h**（不把原长连接缩成默认 10m），回环 PROXY header 解析 **3s**；每条仅一个确定上游，禁止跨 Web/REALITY fallback 和自动重试。socket keepalive 开启但不能把 TCP keepalive 当应用数据。已有 HTTP/WebSocket/DERP 3600s 等 location 超时不随本次改变；2 分钟仅部署恢复预算，不是业务长连接超时。

§12.2 收口结论：

1–5 查询/索引/SARGability/分页/投影/扫描量：无数据库查询变更，不适用。
6–8 批写/乐观锁/tenant 谓词：无数据库写路径，不适用；部署文件写采用主机锁和哈希 guard。
9 调度：续期统一 03:00 DNS cron；不新增高频轮询任务，部署与续期互斥，禁止抢占同一配置。
10 超时/重试/DLQ：如上；无消息队列/DLQ，探测有限次数，失败自动恢复而非无限 retry。
11 并发：固定 Nginx worker 与有界 connection slots，无自建无限线程池；已有 sing-box 高 NOFILE 不等于实际可支持该并发数。
12 缓存：不改应用/DNS 缓存，不引入新缓存失效路径。
13 契约/WAF：原 TLS 字节透传，不改业务 JSON/body/上传限制；Web backend 接受 PROXY、REALITY raw TLS，必须分别写契约测试。vs 保持 DNS-only，现有 Web 域的 Cloudflare 设置不变。
14 可观测：新增 `/var/log/nginx/stream-access.log`，记录来源、SNI、选中上游、状态、收发字节、时长；不记录鉴权值/明文 payload。沿用 `/var/log/nginx/*.log` daily/14/compress；sing-box journald 不开 debug。用 stream 502/connect errors、业务非预期状态、证书失败、FD/连接数判断回归。
15 前后对比：下表是已测 before；after 尚未执行，须用同一命令复测，不以 root URL 404 当迁移失败或自动改断言。
16 增长性债务：流式转发无全量缓冲/扫描；日志有 14 天轮转。单机故障域与缺少历史延迟指标是现状限制，不在本次强行增加监控平台；后续容量提升需单独任务。

### 已测 Web 基线（本机回环路径，非外网用户网络验收）

全部站点用实际域名作 SNI，curl --resolve 指到 127.0.0.1 与 ::1，CA 校验通过，IPv4/IPv6 根路径返回一致：

| 域名 | 根路径状态 |
|---|---|
| auth.signal-align.com | 307 |
| identity.signal-align.com | 404 |
| login.signal-align.com | 404 |
| bandwagon.signal-align.com | 200 |
| headscale.signal-align.com | 200 |
| derp.signal-align.com | 200 |
| ntfy.signal-align.com | 200 |
| books-and-articles.desmondchen.com | 200 |
| api.books-and-articles.desmondchen.com | 404 |
| reading-app.desmondchen.com | 200 |
| api.reading-app.desmondchen.com | 404 |

09:52 补测专门健康路径：auth `/health/ready`、identity `/health/ready`、login `/health`、derp `/derp/probe`、headscale 与 bandwagon `/health`、ntfy `/v1/health` 均返回 **200**，CA 校验通过（本机 IPv4 回环）。证书 SAN 和有效期已读取：最早为 auth 三域证书 2026-12-06；不因迁移重签，after 检查链/主机名并对比 fingerprint。WebSocket/DERP 是额外握手/连接契约检查，完整业务 E2E 只在用户明确要求时运行；本次正常 HTTP/代理健康探测不冒充业务 E2E。

## 设计批准项

请求批准这一组合：方案 A + 默认外部目标 www.cloudflare.com + 以 umbrella 的 host-only Release CD 发布（含必要 pipeline/源码变更）+ DNS-only 保持不写 + 新凭据入 westus2 Vault + 三证书改 DNS 续期/单调度 + 2 分钟共享 Nginx 维护/恢复预算（长连接可能重连，旧节点切换时失效）。同时请确认切换时没有其他 Nginx 配置作业。批准后才进入 writing-plans 与实施仓库 issue/分支流程。未获得批准不得卸载、安装、签发证书或切换。

## 参考

- https://github.com/233boy/sing-box
- https://github.com/SagerNet/sing-box/releases/tag/v1.14.4
- https://sing-box.sagernet.org/configuration/shared/tls/
- https://nginx.org/en/docs/stream/ngx_stream_ssl_preread_module.html
- https://nginx.org/en/docs/stream/ngx_stream_proxy_module.html
- https://raw.githubusercontent.com/SagerNet/sing-box/v1.14.4/option/inbound.go

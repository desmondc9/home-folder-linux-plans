# 实施记录

状态：仅本机必要配置的迁移已完成；用户已确认Android v2rayNG实机连接成功，并在本轮明确授权脱敏档案commit/push。此前“仅本地Git”限制现对本次脱敏档案发布放开，不重新授权业务仓库/框架/CD改动。#68已由#69撤销（main=2ba67fd，与#68前44a084d内容一致）。

最终权威记录：[final-state.md](./final-state.md)；实际配置脱敏快照：[final-config/README.md](./final-config/README.md)。

## 当前本机操作

- [x] 正式备份：`/var/backups/sing-box-migration/2026-10-29-111755-local/original.tar.gz`（root目录0700、文件0600，含旧core/脚本/配置/service、Nginx、auth链接目标、LE证书和DNS凭据、续期调度、UFW规则）。
- [x] SHA256：`b0b2d9d2a32535020a38971a27bba01365a107ebac3f9c72f2167fdeb2a0a6a3`；已试解包并验证关键内容、owner/mode、symlink。原始备份不入Git，至少保留30天。
- [x] 官方1.14.4安装到 `/usr/local/lib/sing-box/1.14.4/`，校验官方archive摘要；新建非登录sing-box用户，生成全新UUID/X25519/short ID，不入Git、不在聊天中打印。
- [x] 回环预览：新core24443 + 临时Nginx15443，两层stream后IPv4/IPv6 REALITY代理均HTTP200。原11域状态/跳转/CA/证书一致，7个health均200，所有非listen/real_ip指令保持。
- [x] bandwagon/derp/headscale三张证书通过官方Certbot5.8 reconfigure的真实DNS-01 staging验证（39.3/38.8/39.6秒），改为dns-cloudflare+null installer；活跃证书文件与derper PID未变。
- [x] 原7个renewal profile均DNS、无nginx installer；保留原03:00 DNS cron并增加reload前nginx -t，停用不支持DNS插件的旧系统timer。旧系统cron带systemd guard，不运行。
- [x] Cloudflare只读核实：vs灰云CNAME→bandwagon，后者灰云A/AAAA正确，无需DNS写入。
- [x] 本机Nginx stream + ssl_preread接管双栈443，Web TLS仅回环14443，PROXY解包中继24444，新core仅回环24443；未改业务项目源码或CD。
- [x] 正式443分别经127.0.0.1、::1、vs.signal-align.com验证REALITY vision代理HTTP200；以最终私有client.json、desmond用户再测HTTP200。
- [x] 最终11域IPv4/IPv6的root状态/跳转/CA/证书及7个health一致；实测Web原始IPv4/IPv6来源保留；独立18790证书不变，其他应用容器未重启。
- [x] 旧 `/etc/sing-box/sh` 与sb入口不再存在；旧core/脚本/vendor unit仅留root受限备份。新sing-box CLI链接官方core，local unit启用开机启动，User=sing-box、零capability、NRestarts=0。
- [x] 删除45575的IPv4/IPv6旧UFW放行；旧45574/45575/39586不再监听。临时preview/client单元、运行时凭据副本、测试容器/API/测试镜像已清理。
- [x] 外部设备验收：用户2026-10-29确认Android手机v2rayNG实测可以连接；未提供版本/运营商/IP族，不虚构单独公网IPv6验收。

auth 的sites-enabled链接已指向 `/etc/nginx/sites-available/auth-local-edge` 的本机副本，`~/signal-align-auth/nginx-auth.conf` 与原始SHA一致，未编辑。未来auth路由调整需人工同步本机副本；其他vhost保留原路由，仅调整内部TLS监听、real_ip及必要的port_in_redirect设置。

私有客户端文件（0600、目录0700）：`~/.config/sing-box-client/vs.signal-align.com/2026-10-29-111755-local/client.json` 与 `client-uri.txt`。正式443连接已启用；URI包含全新认证值，不能提交Git或复制进公开文档。不安装永久测试框架。

### 切换与兼容性修正

- 首次正式尝试因本人unit的RestrictAddressFamilies遗漏AF_NETLINK，core初始化netlink失败；自动恢复旧服务共15.44秒，并核实原11域恢复。未把该次失败当作完成。
- 用户确认后，仅补AF_NETLINK（仍无NET_ADMIN/任何capability），先以完整正式sandbox属性预览验证稳定启动/代理HTTP200，再切换。成功轮总操作9.14秒，Nginx重启5.17秒，core零重启。
- 发现静态目录自动跳转暴露内部14443；经用户确认给11个内部Web TLS server补port_in_redirect off并平滑reload，Nginx master PID不变。reading/books的/assets重定向现为正常外部HTTPS默认端口，实际静态资源200。
- 所有原始备份与失败尝试的新配置均留在root0700的备份目录；原始archive0600及sha256文件保留至少30天。没有上传原始配置、私钥、UUID或客户端URI。

回退注意：原安装archive不含后来创建的 `/etc/systemd/system/sing-box.service`。回退时需先保留/移走新配置并移除这个local override，再恢复旧core/配置、vendor unit、CLI链接和原Nginx树，daemon-reload、重新enable旧unit；仅按需加回45575规则，不盲目覆盖后续防火墙改动。DNS续期也兼容旧Web布局，不必重新启用旧系统Certbot timer。实际回退前必须核对后续人工修改，避免丢失用户工作；本次已实际回退成功一次。

### 性能与容量（实际本机门禁）

触发网关路径与证书外部调用；无DB/缓存/业务应用变更。保留原worker_connections=768和worker数量，不额外调大资源。Web/REALITY约4个Nginx connection slots/完整连接，个人低流量基线下有余量，但未压测、不承诺额定吞吐。stream preread10s、回环connect3s、idle24h；core目标connect5s/TLS握手15s，沿用既有Web长连接超时。stream日志沿用/var/log/nginx/*.log每日/14份轮转并与access.log一致权限；续期仍为原03:00 cron，没有新增周期任务。故障看systemd journal、stream连接日志和既有域名health；本机实测不代表外部网络可达性。

## 历史记录（下述三阶段仓库方案已停止，不再执行）

- [x] 读取 `~/plans/CLAUDE.md`：此档案库直接 main commit/push，无 worktree/issue/PR；公开仓库禁止秘密入库。
- [x] 检查现有 Git 状态并 fetch；保留原有未跟踪的其他任务目录，不纳入本次提交。
- [x] 只读检查系统、sing-box 版本及脱敏入站摘要、Nginx 监听拓扑、UFW、DNS 与官方 release。
- [x] 记录初步需求、证据及不能确定的根因；没有导出或提交现有认证值。
- [x] 用户选择 A（vs 作连接域名，外部站点作 REALITY SNI）。
- [x] Cloudflare API 只读确认 vs 已是灰云 CNAME；无需修改 DNS。
- [x] 读取证书续期/调度、auth 源码与发布入口，fetch 对齐最新 origin/main（保留旧 checkout）。
- [x] 获取 Web 双栈状态/证书、目标 TLS、容量和可用日志基线；凭据未输出。
- [x] 编写完整设计：PROXY 分流中继、源码/CD 发布、KV 来源、受控切换和自动恢复。
- [x] 独立 builder-check 审阅：明确旧节点在切换时失效（不并行保留）、2 分钟包含恢复预算、续期预检在窗口前、外部用户验收在窗口后；已修订 spec，待用户批准。
- [x] 用户了解 host-only CD 扩展范围后回复「好的, 继续」，进入实施规划；实际维护时机/并发作业仍需切换前确认。
- [x] 创建 [umbrella#67](https://github.com/desmondc9/signal-align-umbrella/issues/67)，包含原始目标和可验证验收标准。
- [x] 编写三阶段计划并自审覆盖范围/接口/测试/故障情形；阶段 1/2 仅合并惰性工具，不发布生产。
- [x] 用户确认 Native；本人在隔离 worktree 实施，阶段末独立审阅。
- [x] 阶段 1 Task 1：配置/凭据 API，7 测试 RED→GREEN；官方核心校验配置成功。
- [x] 阶段 1 Task 2：严格 release selector，6 测试 RED→GREEN。
- [x] 阶段 1 Task 3：Nginx 候选与容器内18项真实协议验证；既有9项脚本测试不回归。
- [x] 阶段 1 全分支独立审阅：后端身份/路径与证书lineage盲点补强；三类错误候选变异均被捕获。
- [x] 阶段 1 [PR #68](https://github.com/desmondc9/signal-align-umbrella/pull/68)，最终提交6f13183；CI的changes/scripts通过，其他未涉及job按条件跳过。
- 历史后续：#68曾获批合并，随后用户纠正为本机运维并要求撤销；已由#69回退。阶段2草稿未推送、未部署，阶段3框架取消。
- 原仓库发布计划不再执行；本机备份/回退、迁移、DNS-only验证、既有应用验证和最终验收证据以上方当前记录为准。

## 文档与 Git

只提交本任务文档、明确脱敏的配置快照和 README 索引。真实备份及真实客户端配置存仓库外，不能随文档跟踪。本机无 `~/Notebook`，没有可同步的本地域笔记。本轮仅按用户新授权推送该档案仓库。

## 原分阶段实施入口（已取消，仅供历史追溯）

1. [协议与候选配置](./implementation-phase-1.md)：配置、严格 selector、Nginx PROXY/REALITY 协议契约，生产不变。
2. [备份与限时恢复](./implementation-phase-2.md)：备份/漂移、续期预检、systemd watchdog 的故障注入，生产不变。
3. [Release/CD 与生产迁移](./implementation-phase-3.md)：仅host发布入口、auth后续兼容、PR/CI/合并后受控部署与外部验收。

实施仓库遵循本身的 plans 文件名约定（implementation_plan_phase_01.md 等）；本目录保留公开脱敏的总体主档。阶段1/2可各自独立合并惰性工具，只有阶段3在获准维护时机触发生产发布，避免实现尚未齐全就改在线auth listener。

阶段1运行证据见 [phase-1-results.md](./phase-1-results.md)。此处「验证通过」仅指隔离候选环境，不代表本机生产已迁移。

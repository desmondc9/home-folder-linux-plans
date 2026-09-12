# home-folder-linux-plans

这台 Linux 机器（Kubuntu 26.04）上，本机开发环境配置类任务（非某个代码仓库内的功能开发）的记录仓库。每个任务一个目录，遵循 `~/CLAUDE.md`「Development, testing, & debugging workflow」里 `spec.md` / `implementation.md` 的记录方式：

- `spec.md` — 背景与目标、范围（in/out）、现状分析（root cause）、解决方案、验收标准、风险与缓解、参考。
- `implementation.md` — 对应 spec.md 的任务清单（`- [x]`）、变更文件表、验证方式、备注（含可迁移经验/教训）。

目录命名：`YYYY-MM-DD-HHMM-topic/`，时间戳前缀即任务开始时间（精确到分钟，便于同一天的多个任务按真实顺序排列；遵循 `~/CLAUDE.md` 的 `plans/YYYY-MM-DD-HHMM-[topic]/` 约定）；文档之间用相对链接互相引用，方便串联查阅。macOS 机器上的同类仓库见 [home-folder-mac-plans](https://github.com/desmondc9/home-folder-mac-plans)。

## 任务索引

按时间顺序排列——后期的任务在 spec.md/implementation.md 里可能引用更早任务的结论：

| 时间 | 目录 | 主题 |
|---|---|---|
| 2026-07-01 12:30 | [wine-windows-apps](./2026-07-01-1230-wine-windows-apps/) | Wine 跑 Windows 应用（微信等）的安装、HiDPI/混合 GPU、语音输入（Pulse→ALSA 后端）与电话/摄像头/远程控制等一系列排查 |
| 2026-07-02 08:58 | [rime-wubi-shuangpin](./2026-07-02-0858-rime-wubi-shuangpin/) | fcitx5 + Rime 五笔/双拼输入方案：码表加载顺序、custom 补丁与重启方式 |
| 2026-08-18 22:24 | [tailnet-exit-singbox](./2026-08-18-2224-tailnet-exit-singbox/) | 自建 headscale tailnet 双 Exit Node（笔记本 + VPS）+ sing-box 分流网关：国内直连/国外经 VLESS-Reality/自定义规则；含两日排查的内核 martian source 根因档案（`accept_local` 修复）与完整踩坑清单 |
| 2026-08-19 13:02 | [sunshine-moonlight-tailnet](./2026-08-19-1302-sunshine-moonlight-tailnet/) | iPad/Android 经 Moonlight+Sunshine 串流笔记本：自建 tailnet 主链路（IPv6 P2P）+ frp 备份链路双冗余；含 0819 开机端口冲突僵尸态排查与 1 分钟看门狗，附日常运维速查 |
| 2026-08-19 13:17 | [touchpad-three-finger-drag](./2026-08-19-1317-touchpad-three-finger-drag/) | macOS 式三指拖拽（linux-3-finger-drag）：文件位置、dragEndDelay=250、更新方式 |
| 2026-08-19 14:14 | [cloudflare-zerotrust-removal](./2026-08-19-1414-cloudflare-zerotrust-removal/) | 移除 Cloudflare Zero Trust 本机残留（cloudflared/warp purge + 手动 systemd 单元 + apt 源 + ssh config 条目） |
| 2026-08-19 14:20 | [frp-config-archive](./2026-08-19-1420-frp-config-archive/) | frp 双端配置实体档案：本机 frpc + VPS frps 的 toml/systemd 快照（token 已脱敏）、SSH:6000 + Sunshine 端口矩阵、allowPorts 白名单与日常运维 |
| 2026-08-19 14:30 | [headscale-custom-derp](./2026-08-19-1430-headscale-custom-derp/) | 自建 DERP 兜底（region 998，derp.signal-align.com）：独立 derper + nginx 443 反代 + STUN 3479，与内嵌 999 共存 |
| 2026-08-19 15:28 | [frp-token-redaction](./2026-08-19-1528-frp-token-redaction/) | 安全事故：frp token 误提交到**公开**仓库——filter-repo 清历史 + 强推 + 全历史机密排查（gitleaks）+ token 轮换；据此新建 [CLAUDE.md](./CLAUDE.md) 机密红线规则 |
| 2026-08-19 16:33 | [sunshine-display-switch](./2026-08-19-1633-sunshine-display-switch/) | Sunshine 显示器切换（output_name 只认数字）+ DPMS 关屏=串流必死（500/503）根因与 screen-wake-daemon / watchdog 唤醒体系 |
| 2026-08-19 17:38 | [dockur-windows11-vm](./2026-08-19-1738-dockur-windows11-vm/) | dockur/windows Win11 25H2 VM（rootless podman）：8C/16G/128G、RDP 3389 / Web 8006 / SSH 2222 仅 localhost、`winvm` 管理命令 |
| 2026-08-20 12:52 | [redroid-android-container](./2026-08-20-1252-redroid-android-container/) | redroid Android 15 容器（rootful podman）：SwiftShader 软渲染、OnePlus PJZ110 七文件 spoof、ARM 翻译层、tproxy 表 100 致 netavark MTU 65536 坑 |
| 2026-08-20 20:01 | [windows11-vm-backup](./2026-08-20-2001-windows11-vm-backup/) | Win11 VM 备份（qcow2 + state tarball，归档并提交） |
| 2026-08-20 20:32 | [redroid-backup](./2026-08-20-2032-redroid-backup/) | redroid 数据备份导出（data/ 卷，有效性未确认） |
| 2026-08-20 21:27 | [sunshine-dpms-off-fix](./2026-08-20-2127-sunshine-dpms-off-fix/) | Sunshine RTSP 500/503 根因 = PowerDevil DPMS 关屏杀 KMS 抓屏：TurnOffDisplayIdleTimeoutSec=0 修复 |
| 2026-08-21 09:17 | [kernel-7.0.0-30-boot-binderfs-race](./2026-08-21-0917-kernel-7.0.0-30-boot-binderfs-race/) | binderfs fstab 行与 systemd-modules-load 开机竞态致启动失败：nofail + x-systemd.after 修复 |
| 2026-08-21 10:16 | [hdmi-frl-screen-blank](./2026-08-21-1016-hdmi-frl-screen-blank/) | 4K@160 FRL 链路训练失败致闪黑：降 4K@60 + DPMS 自愈 + 唤醒 daemon/取证监控增强 |
| 2026-08-21 15:11 | [sunshine-notebook](./2026-08-21-1511-sunshine-notebook/) | Sunshine/Moonlight 知识重组为 Obsidian 风格 Notebook（~/Notebook/Sunshine-Moonlight-串流/）：MOC + 6 笔记 + wikilink 约定 |
| 2026-08-22 09:08 | [kscreen-doctor-crash-loop](./2026-08-22-0908-kscreen-doctor-crash-loop/) | screen-wake-daemon 开机竞态致 kscreen-doctor SIGABRT 循环：unit 排序 + 脚本环境守卫修复 |
| 2026-08-22 10:24 | [singbox-notebook](./2026-08-22-1024-singbox-notebook/) | sing-box/tproxy 知识重组为 Obsidian 风格 Notebook（~/Notebook/sing-box-分流网关/）：MOC + 6 笔记（架构/配置/TPROXY/DNS/运维/深坑），跨域与 Sunshine MOC 互链 |
| 2026-08-22 11:30 | [tailscale-notebook](./2026-08-22-1130-tailscale-notebook/) | tailscale/headscale/DERP 知识重组为 Obsidian 风格 Notebook（~/Notebook/Tailscale-Headscale-DERP/）：MOC + 7 笔记（架构/控制面/节点打洞/DERP/双出口/运维/深坑），与 Sunshine、sing-box 域 MOC 互链 |
| 2026-08-22 11:55 | [notebook-readme](./2026-08-22-1155-notebook-readme/) | ~/Notebook 纵览 README：三域按依赖排序（组网层 tailnet → 网关层 sing-box → 应用层 Sunshine），症状索引 + 共同约定 + 仓库信息 |
| 2026-08-22 14:04 | [android-singbox-client](./2026-08-22-1404-android-singbox-client/) | Android sing-box (SFA 1.13.19) 客户端配置：与本机 `/etc/sing-box/config.json` 的 DNS/流量分流与 ruleset 语义 1:1 对齐，在 redroid 容器内实测验证;2026-09-12 v3 升级为**一体化单 VPN**(内嵌 tailscale endpoint 连 headscale + tailnet 网段路由到 ts-ep + MagicDNS),解决 Android 单 VPN 下 SFA×Tailscale 互斥,真机验证通过(oneplus-15-sfa=100.64.0.8) |
| 2026-08-22 23:02 | [exfat-mount-fix](./2026-08-22-2302-exfat-mount-fix/) | exFAT U 盘挂载失败：kernel.modprobe sysctl 被清空致模块按需加载失效（写入者未定，crun/conmon 已源码排除）；modules-load.d 预加载 + sysctl 恢复修复 |
| 2026-08-22 23:54 | [browser-hevc-bilibili](./2026-08-22-2354-browser-hevc-bilibili/) | Chrome/Edge 报"浏览器不支持 HEVC"：独显直连 + 无 NVIDIA VAAPI 驱动 + Chromium 默认跳过 NVIDIA + 特性开关未开四层叠加；nvidia-vaapi-driver + 三特性 flags + ksycoca 重建修复 |
| 2026-08-22 23:59 | [konsole-autoswitch-removal](./2026-08-22-2359-konsole-autoswitch-removal/) | 拆除 Konsole 随系统主题自动切换 rig 的自动部分（开机 kdeglobals 未落定误判 light）；保留手动 Meta+Shift+T toggle，默认 profile 修正为 Dark |
| 2026-08-23 09:58 | [codec-capability-audit](./2026-08-23-0958-codec-capability-audit/) | 音视频编解码能力审计：浏览器侧完整（H.264/HEVC/AV1 均 NVDEC 硬解，VP9 硬解为 Chromium+NVIDIA 已知限制）；OS 侧补 GStreamer bad+vaapi，解锁 gst-vaapi 驱动白名单（GST_VAAPI_ALL_DRIVERS=1） |
| 2026-08-24 09:37 | [discover-packagekit-proxy-db](./2026-08-24-0937-discover-packagekit-proxy-db/) | Discover 报连旧代理：PackageKit transactions.db proxy 表僵尸行（SetProxy 上报，与 kioslaverc/apt 无关）；清 10 行 + 重启服务修复 |
| 2026-08-24 11:27 | [hdmi21-4k120-test](./2026-08-24-1127-hdmi21-4k120-test/) | HDMI 2.1 满血线验证：4K@160 压测通过 = FRL 实锤，4K@120 稳定；换线解决 |
| 2026-08-26 14:58 | [chrome-wayland-dark-mode](./2026-08-26-1458-chrome-wayland-dark-mode/) | Linux Wayland + Chrome light/dark 自动切换（三阶段合一）：① DR "Use system color scheme" 警告=Linux 硬编码文案，CDP 实证 KDE→portal→Chrome 链路健康；② Chrome 原生暗色调研：UI 跟随原生可用、内容变暗仅 #enable-force-dark、DR 仍最优、Stylus 为大站轻量替代；③ Chrome 历史+CDP 双遍实测筛 11 个原生跟随配色的站点加入 DR disabledFor，含 sync LevelDB 解析器 |
| 2026-08-30 20:49 | [agentmemory-setup](./2026-08-30-2049-agentmemory-setup/) | agentmemory 跨 agent 记忆层（Claude Code + opencode 共用一个本地记忆服务器）：33 条原生 memory 迁入、systemd 自启、embedding/LLM 选型基准（qwen3-embedding:4b + Kimi k3）、定位并绕过向量索引重启失效的上游缺陷；含可复现的基准测试脚本 |
| 2026-08-30 21:19 | [scalability-verify-gate](./2026-08-30-2119-scalability-verify-gate/) | 开发流程加装「性能验收门禁」：~/CLAUDE.md 新增 Step E（提 PR 前强制过关）+ Step A/B/C 三个前置触发点；~/docs/scalability-review-checklist.md 重构（139→382 行），新增 §0.1 先查监控再问人（GCP/Azure/Grafana 取数速查 + 七条取数坑）、§0.2 infra 家底盘点（含硬限制专表）、§12 verify 门禁，并补入 20+ 条来自真实生产事故的教训 |
| 2026-09-01 21:11 | [opencode-slow-startup](./2026-09-01-2111-opencode-slow-startup/) | opencode 启动 8.2s 根因:Azure provider loader 每次启动同步阻塞跑 `az cognitiveservices account list`(本机 5.7s,GFW 后访问 Azure 管理端点);wrapper 注入 `AZURE_RESOURCE_NAME` 短路 → TTFD 2.5s。**`disabled_providers` 无效**(loader 先于过滤执行);已实测排除 526MB DB / models.dev 下载 / 插件 / 5 个 MCP |
| 2026-09-02 21:39 | [openclaw-doctor-fixes](./2026-09-02-2139-openclaw-doctor-fixes/) | OpenClaw doctor 全量修复:umask 002 导致 systemd 目录链组可写(unsafe-permissions)、明文 secret 迁 SQLite store、memory search 用 local embedding、Kimi web search 发现 coding plan key 只认 `api.kimi.com/coding` 端点。晚间追加:nvm prefix 警告修复 → npm-global 全局包迁回 nvm → 连带修复指向已删路径的 gateway systemd 服务(drop-in 664 再踩 unsafe-permissions)→ 配置 `moonshot/kimi-k3` 为 glm-5.3 的自动 fallback。深夜追加:kimi-claw 官方桥接脚本与 2026.8.2 三处不兼容(注入非法 plugins.installs 键 / deprecated flag / 缺 capability consent),本地打补丁跑通,桥接已上线 |
| 2026-09-03 18:24 | [sing-box-block-outbound-fix](./2026-09-03-1824-singbox-block-outbound-fix/) | youtube 等代理网页打不开:急性=用户手动 stop 服务 4 分钟全量黑洞(自愈);慢性=sing-box 1.12+ 已移除内置 `block` 出站而 config.json 仍引用(1.13.19 下 7199+ 次 `outbound not found: block`)→ 改用规则动作 `action: reject` 修复 |
| 2026-09-03 20:47 | [futu-domain-audit](./2026-09-03-2047-futu-domain-audit/) | 富途牛牛 Linux 版端点清单采集与 sing-box 全量代理分流:域名运行时下发+裸 IP(腾讯云国际×3+江苏电信行情线),tcpdump/mitmproxy/二进制静态扫描多管齐下;37/37 验收+实机含交易全量 proxy 通过,规则可供手机端复用 |
| 2026-09-04 16:32 | [nvim-icon-nerd-font-fix](./2026-09-04-1632-nvim-icon-nerd-font-fix/) | nvim tabline/dashboard 图标豆腐块:Konsole 默认字体 Noto Mono 无 Nerd Font PUA 字形(fc-list 证据链确认,与 nvim 配置无关)→ 安装 Nerd Font 版字体并改 Konsole profile,重启生效 |
| 2026-09-05 00:40 | [lazyvim-learning-workspace](./2026-09-05-0040-lazyvim-learning-workspace/) | LazyVim 替代 IDE 学习工作区（teach 流程,~/learning/lazyvim,4 课 3 验证+五语言练习仓）+ LSP 全家桶体检：nvim 0.11.6→0.12.5（~/.local,可回滚）、Go 1.27.1+gopls（Mason golang 包=本地编译,无工具链静默失败;LazyVim 对 Mason 认识的服务器交 mason-lspconfig automatic_enable 只启用已装包）、rust-analyzer 组件修复（rustaceanvim 硬门禁 nvim≥0.12）、13 extras、autoformat 关闭;11 门语言 attach 实测全绿 |
| 2026-09-05 10:43 | [jdtls-preparerename-fix](./2026-09-05-1043-jdtls-preparerename-fix/) | jdtls 1.60 prepareRename 在 ups-hms-backend 全项目失效（"Renaming this element is not supported"）而 hover/跳转/完整 rename 全正常：八轮嫌疑逐一排除（含 Lombok 冤案——复现坐标打错,自纠平反）,定位到服务器侧 OccurrencesFinder 通路 + nvim 0.12 动态能力注册机制（registerCapability 改写 prepareProvider 为唯一有效注入点,三条常规能力覆盖路径均被 legacy start_or_attach 绕过）;无头端到端验证 2 文件 rename 落位 |
| 2026-09-06 18:47 | [opencode-serve-systemd](./2026-09-06-1847-opencode-serve-systemd/) | opencode 以 systemd user service 常驻暴露（0.0.0.0:4096 + Basic Auth,供 Android opencode-mobile 经 Tailscale 远程连入）：密码 0600 env 文件注入不入库、ExecStart 直指真实二进制避开 wrapper 的 PATH 自解析但保留 AZURE 探针短路、enable-linger 免登录自启、curl 鉴权矩阵 401/200/401 验证 |
| 2026-09-06 21:05 | [openclaw-gateway-repair](./2026-09-06-2105-openclaw-gateway-repair/) | OpenClaw v2026.9.2 装后网关不起：4 月旧 unit 残留（指向已换的 nvm 路径）+ `gateway install --force` 被 664 组可写权限拦截（umask 002 环境性根因）→ chmod go-w 后重装 unit,新路径/密钥运行时加载/16007M heap,status --deep 全绿 |
| 2026-09-06 21:45 | [openclaw-glm-mcp-hardening](./2026-09-06-2145-openclaw-glm-mcp-hardening/) | OpenClaw 默认模型切 zhipu glm-5.3（zshrc 槽位映射,glm-5.3[1m] 已下线实测）+ 4 个智谱 MCP + doctor 加固：8 处明文密钥迁 SQLite store、feishu/whatsapp 渠道关闭,infer/mcp probe/doctor findings 4→1 验证 |
| 2026-09-06 22:20 | [openclaw-tailnet-tls-exposure](./2026-09-06-2220-openclaw-tailnet-tls-exposure/) | OpenClaw 经 tailnet 暴露给手机（Android 配对硬性要求 real TLS）：自建 headscale 下 tailscale serve/funnel 501 不可用（LE 仅官方 ts.net）→ acme.sh DNS-01 真证书 + bind=custom 100.64.0.1 tailnet-only + publicOrigin,ACME 续期 cron 自动重启网关;含 Android 配对步骤与完整回滚 |
| 2026-09-06 23:25 | [openclaw-local-hardening](./2026-09-06-2325-openclaw-local-hardening/) | OpenClaw 本机查漏补缺（对照服务器 playbook,grilling 两轮定位）：systemAgent=main 消 AGENT_SELECTION 报错风暴、weixin 渠道停用留服务器、memory 切本地 llama-cpp embedding（Azure 退场,163 文件重建索引）、GitHub token 走 gh keyring→store、备份体系上线（清死链技能与旧 .venv 后 verify 通过 + 24h）;坑:memory index 无 TTY 挂死=成本确认等 stdin |
| 2026-09-07 14:05 | [printer-mdns-to-static-ip](./2026-09-07-1405-printer-mdns-to-static-ip/) | 打印机任务卡死 "Unable to locate printer":队列 device-uri 是 mDNS 服务名而非固定 IP(WiFi+家用路由组播时好时坏),固定了 IP 但队列没用它 → `lpadmin` 切 `ipp://192.168.31.199/ipp/print` 直连去 mDNS 化,测试页 35s 完成验证;经验:ipps 自签证书信任坑用明文 ipp 规避、mDNS 主机名尾段=MAC 可反查 IP、zsh 无 /dev/tcp 探端口要用 nc |

| 2026-09-07 15:22 | [lazyvim-vps-replay](./2026-09-07-1522-lazyvim-vps-replay/) | 按 2026-09-05-0040 清单在 Bandwagon VPS 重放 LazyVim 全套(nvim 0.12.5/Go 1.27.1/rustup/JDK21/Mason×20/extras×13),去国内镜像直连;新坑:json-ls 更名 json-lsp、headless 需 vim.wait 等 Mason 队列清空;六语言 LSP 稳定等待法验证全过 |

| 2026-09-11 10:12 | [restic-azure-backup](./2026-09-11-1012-restic-azure-backup/) | restic → Azure Blob(East Asia)每日备份体系(原实体机 yaoshi15pro):单仓库单快照、root systemd 双 timer(03:00 备份/周日 prune+check)、manifests+dotfiles 打捞钩子、14d/8w/6m 保留;事故:apt restic 无 azure 后端→官方二进制、systemd EnvironmentFile 不认 export→bash -c source 模式;首备 73.2 GiB 实存/33 分钟 |

| 2026-09-11 21:00 | [restic-azure-backup-wsl](./2026-09-11-2100-restic-azure-backup-wsl/) | WSL 机(DESKTOP-J7NBNU4)按母方案重建备份,同仓库 host 区分(用户确认;恢复的 45G 块已在库,首备仅 4.5 分钟);wsl.exe -u root 替代 sudo 保住 root timer 架构;include 裁剪去 tailscale/crontabs;事故:超时 restore 留陈旧锁→forget exit 11→unlock 修复;forget 按 host 分组作用于全部机器快照属预期语义 |

| 2026-09-11 21:36 | [opencode-tui-keybinds-wsl](./2026-09-11-2136-opencode-tui-keybinds-wsl/) | 取消 opencode 中 ctrl+c / ctrl+shift+c 退出:默认 app_exit 绑 ctrl+c,且 Windows Terminal 无选中时两键同发 0x03,故改 tui.json 一个键名即双解;键绑定不在 opencode.json(schema 拒未知键)而在独立 ~/.config/opencode/tui.json(两套 schema);配置由灾备恢复落位,本机零修改仅验证;TUI 配置不热更新,重启生效 |

| 2026-09-11 21:42 | [sdkman-jdk21](./2026-09-11-2142-sdkman-jdk21/) | 官方脚本装 sdkman 5.23.0 + Temurin JDK 21.0.12+1.1-tem 设默认(JAVA_HOME 由 sdkman 托管);坑:安装脚本硬依赖 unzip+zip 但 sudo 无免密 → 用户手装、轮询等待(两轮);zip 仅存在性检查、安装只用 unzip(脚本源码核对);安装器自动补 ~/.bashrc 与 ~/.zshrc 片段,zsh 零手工配置 |

| 2026-09-11 21:20 | [podman-wsl-ubuntu-native](./2026-09-11-2120-podman-wsl-ubuntu-native/) | WSL 弃用 Windows 共享 machine 改 Ubuntu 原生 rootless podman(根因:跨发行版 bind-mount 不支持,podman#21813);Ubuntu/Debian 默认不配短名解析致 `podman pull nginx` 报错 → 用户级 registries.conf + daocloud/1ms 双 mirror;docker-compose-v2 symlink 成 podman compose provider + user socket + linger;坑:恢复的 .git/config 残留 10809 代理致 git 全卡(unset + ssh.github.com:443 推送)、gitleaks 直连 GitHub 可用;Windows 侧清理与 Podman Desktop docker-context 桥接实验待用户手动 |
| 2026-09-12 00:21 | [windows11-exit-node-singbox](./2026-09-12-0021-windows11-exit-node-singbox/) | Windows 11 物理机成为第三 Exit Node:sing-box 1.13.19 Windows 版 TUN(auto_route)替代 TPROXY/nftables,分流规则与笔记本逐行平移(含 `action: reject` 修复);三出口并存(笔记本/Windows/VPS);AI 经 WSL mirrored interop 摸底并代跑;Task 5b 修复 process_name 误伤转发流量(Windows 进程归因归属 tailscaled);Task 5c 受控实验定位 **tailscaled Windows 用户态转发 ~8Mbps 天花板**(sing-box 无罪),手机改走 SFA v3 本地分流,Windows 出口保留供轻量/iPad 场景;富途 37 域名 rule-set 平移(futu.json + process_name 兜底 + clash_api) |
| 2026-09-12 13:15 | [lazyvim-dap-setup](./2026-09-12-1315-lazyvim-dap-setup/) | VPS 上 LazyVim 补齐 DAP 调试工具链(nvim 0.12.5 已是最新无需动):启用 dap.core extra、Mason 装 debugpy/delve/js-debug-adapter/java-debug-adapter/java-test、自写 TS/JS 配置(typescript extra 官方不带 dap 接线);python/go 的 dap 插件挂在 nvim-dap 依赖下"加载即配好"而 rustaceanvim 是 ft 惰性,headless 验证须区分加载时机;mason-nvim-dap 只配 adapter 不给 configurations;DAP 接线+LSP 回归(pyright/ruff/vtsls)全绿 |
| 2026-09-12 13:15 | [lazyvim-dap-setup](./2026-09-12-1315-lazyvim-dap-setup/) | VPS 上 LazyVim 补齐 DAP 调试工具链(nvim 0.12.5 已是最新无需动):启用 dap.core extra、Mason 装 debugpy/delve/js-debug-adapter/java-debug-adapter/java-test、自写 TS/JS 配置(typescript extra 官方不带 dap 接线);python/go 的 dap 插件挂在 nvim-dap 依赖下"加载即配好"而 rustaceanvim 是 ft 惰性,headless 验证须区分加载时机;mason-nvim-dap 只配 adapter 不给 configurations;DAP 接线+LSP 回归(pyright/ruff/vtsls)全绿 |

## 关于本仓库

这些记录主要面向"以后回顾自己做过什么、为什么这么做"以及"迁移到新机器时按顺序重放"，不是面向他人协作的项目文档，因此不遵循常规开源项目的 `CONTRIBUTING`/`CODE_OF_CONDUCT` 等惯例。

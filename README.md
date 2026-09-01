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
| 2026-08-22 14:04 | [android-singbox-client](./2026-08-22-1404-android-singbox-client/) | Android sing-box (SFA 1.13.19) 客户端配置：与本机 `/etc/sing-box/config.json` 的 DNS/流量分流与 ruleset 语义 1:1 对齐，在 redroid 容器内实测验证 |
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

## 关于本仓库

这些记录主要面向"以后回顾自己做过什么、为什么这么做"以及"迁移到新机器时按顺序重放"，不是面向他人协作的项目文档，因此不遵循常规开源项目的 `CONTRIBUTING`/`CODE_OF_CONDUCT` 等惯例。

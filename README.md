# home-folder-linux-plans

这台 Linux 机器（Kubuntu 26.04）上，本机开发环境配置类任务（非某个代码仓库内的功能开发）的记录仓库。每个任务一个目录，遵循 `~/CLAUDE.md`「Development, testing, & debugging workflow」里 `design.md` / `implementation.md` 的记录方式：

- `design.md` — 背景与目标、范围（in/out）、现状分析（root cause）、解决方案、验收标准、风险与缓解、参考。
- `implementation.md` — 对应 design.md 的任务清单（`- [x]`）、变更文件表、验证方式、备注（含可迁移经验/教训）。

目录命名：`YYYY-MM-DD-topic/`，日期前缀即任务开始时间（遵循 `~/CLAUDE.md` 的 `plans/[timestamp]-[topic]/` 约定）；文档之间用相对链接互相引用，方便串联查阅。macOS 机器上的同类仓库见 [home-folder-mac-plans](https://github.com/desmondc9/home-folder-mac-plans)。

## 任务索引

按时间顺序排列——后期的任务在 design.md/implementation.md 里可能引用更早任务的结论：

| 日期 | 目录 | 主题 |
|---|---|---|
| 2026-07-01 | [wine-windows-apps](./2026-07-01-wine-windows-apps/) | Wine 跑 Windows 应用（微信等）的安装、HiDPI/混合 GPU、语音输入（Pulse→ALSA 后端）与电话/摄像头/远程控制等一系列排查 |
| 2026-07-02 | [rime-wubi-shuangpin](./2026-07-02-rime-wubi-shuangpin/) | fcitx5 + Rime 五笔/双拼输入方案：码表加载顺序、custom 补丁与重启方式 |
| 2026-08-18 | [tailnet-exit-singbox](./2026-08-18-tailnet-exit-singbox/) | 自建 headscale tailnet 双 Exit Node（笔记本 + VPS）+ sing-box 分流网关：国内直连/国外经 VLESS-Reality/自定义规则；含两日排查的内核 martian source 根因档案（`accept_local` 修复）与完整踩坑清单 |
| 2026-08-18 | [sunshine-moonlight-tailnet](./2026-08-18-sunshine-moonlight-tailnet/) | iPad/Android 经 Moonlight+Sunshine 串流笔记本：自建 tailnet 主链路（IPv6 P2P）+ frp 备份链路双冗余；含 0819 开机端口冲突僵尸态排查与 1 分钟看门狗，附日常运维速查 |
| 2026-08-19 | [touchpad-three-finger-drag](./2026-08-19-touchpad-three-finger-drag/) | macOS 式三指拖拽（linux-3-finger-drag）：文件位置、dragEndDelay=250、更新方式 |
| 2026-08-19 | [cloudflare-zerotrust-removal](./2026-08-19-cloudflare-zerotrust-removal/) | 移除 Cloudflare Zero Trust 本机残留（cloudflared/warp purge + 手动 systemd 单元 + apt 源 + ssh config 条目） |
| 2026-08-19 | [frp-config-archive](./2026-08-19-frp-config-archive/) | frp 双端配置实体档案：本机 frpc + VPS frps 的 toml/systemd 快照（token 已脱敏）、SSH:6000 + Sunshine 端口矩阵、allowPorts 白名单与日常运维 |
| 2026-08-19 | [frp-token-redaction](./2026-08-19-frp-token-redaction/) | 安全事故：frp token 误提交到**公开**仓库——filter-repo 清历史 + 强推 + 全历史机密排查（gitleaks）+ token 轮换；据此新建 [CLAUDE.md](./CLAUDE.md) 机密红线规则 |
| 2026-08-19 | [dockur-windows11-vm](./2026-08-19-dockur-windows11-vm/) | dockur/windows Win11 25H2 VM（rootless podman）：8C/16G/128G、RDP 3389 / Web 8006 / SSH 2222 仅 localhost、`winvm` 管理命令 |
| 2026-08-19 | [headscale-custom-derp](./2026-08-19-headscale-custom-derp/) | 自建 DERP 兜底（region 998，derp.signal-align.com）：独立 derper + nginx 443 反代 + STUN 3479，与内嵌 999 共存 |
| 2026-08-19 | [sunshine-display-switch](./2026-08-19-sunshine-display-switch/) | Sunshine 显示器切换（output_name 只认数字）+ DPMS 关屏=串流必死（500/503）根因与 screen-wake-daemon / watchdog 唤醒体系 |
| 2026-08-20 | [redroid-android-container](./2026-08-20-redroid-android-container/) | redroid Android 15 容器（rootful podman）：SwiftShader 软渲染、OnePlus PJZ110 七文件 spoof、ARM 翻译层、tproxy 表 100 致 netavark MTU 65536 坑 |
| 2026-08-20 | [redroid-backup](./2026-08-20-redroid-backup/) | redroid 数据备份导出（data/ 卷，有效性未确认） |
| 2026-08-20 | [sunshine-dpms-off-fix](./2026-08-20-sunshine-dpms-off-fix/) | Sunshine RTSP 500/503 根因 = PowerDevil DPMS 关屏杀 KMS 抓屏：TurnOffDisplayIdleTimeoutSec=0 修复 |
| 2026-08-20 | [windows11-vm-backup](./2026-08-20-windows11-vm-backup/) | Win11 VM 备份（qcow2 + state tarball，归档并提交） |
| 2026-08-21 | [hdmi-frl-screen-blank](./2026-08-21-hdmi-frl-screen-blank/) | 4K@160 FRL 链路训练失败致闪黑：降 4K@60 + DPMS 自愈 + 唤醒 daemon/取证监控增强 |
| 2026-08-21 | [kernel-7.0.0-30-boot-binderfs-race](./2026-08-21-kernel-7.0.0-30-boot-binderfs-race/) | binderfs fstab 行与 systemd-modules-load 开机竞态致启动失败：nofail + x-systemd.after 修复 |
| 2026-08-21 | [sunshine-notebook](./2026-08-21-sunshine-notebook/) | Sunshine/Moonlight 知识重组为 Obsidian 风格 Notebook（~/Notebook/Sunshine-Moonlight-串流/）：MOC + 6 笔记 + wikilink 约定 |
| 2026-08-22 | [kscreen-doctor-crash-loop](./2026-08-22-kscreen-doctor-crash-loop/) | screen-wake-daemon 开机竞态致 kscreen-doctor SIGABRT 循环：unit 排序 + 脚本环境守卫修复 |
| 2026-08-22 | [singbox-notebook](./2026-08-22-singbox-notebook/) | sing-box/tproxy 知识重组为 Obsidian 风格 Notebook（~/Notebook/sing-box-分流网关/）：MOC + 6 笔记（架构/配置/TPROXY/DNS/运维/深坑），跨域与 Sunshine MOC 互链 |

## 关于本仓库

这些记录主要面向"以后回顾自己做过什么、为什么这么做"以及"迁移到新机器时按顺序重放"，不是面向他人协作的项目文档，因此不遵循常规开源项目的 `CONTRIBUTING`/`CODE_OF_CONDUCT` 等惯例。

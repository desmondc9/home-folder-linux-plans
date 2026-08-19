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

## 关于本仓库

这些记录主要面向"以后回顾自己做过什么、为什么这么做"以及"迁移到新机器时按顺序重放"，不是面向他人协作的项目文档，因此不遵循常规开源项目的 `CONTRIBUTING`/`CODE_OF_CONDUCT` 等惯例。

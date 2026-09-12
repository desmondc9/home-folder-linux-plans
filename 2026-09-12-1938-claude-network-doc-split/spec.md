# CLAUDE.md「Network access from mainland China」章节拆分到 ~/docs

- 日期:2026-09-12 19:38
- 类型:本机 agent 文档重构(无代码变更,无 PR)
- 状态:已完成并验证(正文逐行一致)

## 环境

- **WSL2 Ubuntu**(宿主 Windows 11 物理机 DESSKTOP-J7NBNU4);`~/.config/opencode/AGENTS.md` 是指向 `~/.claude/CLAUDE.md` 的符号链接,Claude Code 与 opencode 共用一份

## 背景

`~/.claude/CLAUDE.md` 的 GFW 网络章节 39 行常驻每个 session 的上下文,但大部分内容(镜像 URL、代理 env 清单、诊断步骤)只在网络真正出问题时才被需要——典型的 progressive disclosure 场景。

## 变更内容

| 项 | 说明 |
|---|---|
| 新建 `~/docs/network-access-china.md` | 完整正文原样迁出(含 10809/10808 端口史、http→https 镜像教训、WSL 摸不到宿主监听的坑),头部注明出处与迁移日期 |
| `~/.claude/CLAUDE.md` 章节 39 行 → 5 行指针 | 触发条件内联保留:①任何网络失败/超时 → 读文档;②**Google/GCP 请求前主动读**(GFW 下 Google 是挂起而非报错,事后读就晚了) |

指针设计要点(writing-for-agents 纪律):
- **留在内联的只有改变指针触发时机的事实**——Google/GCP 挂起陷阱 + 10808 已退役护栏(防好心「纠正」端口;历史上错端口文档耗过一个排查周期)
- 镜像/代理细节单源下沉到文档,不在两处重复(该章节自身的历史教训就是重复会腐烂)

## 验证

- [x] 迁出正文与原文非空行逐行 diff 一致(24/24 行)
- [x] CLAUDE.md 章节结构与符号链接完好(299 → 264 行)
- [x] `~/docs` 非 git 仓库,无需提交;gitleaks 扫描全仓无泄露

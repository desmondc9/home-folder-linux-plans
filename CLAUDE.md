# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

本仓库(`home-folder-linux-plans`)是家目录系统配置任务的设计/实施档案库,托管在 GitHub 且为 **公开仓库**(https://github.com/desmondc9/home-folder-linux-plans)。每个任务一档:`[日期]-[主题]/design.md` + `implementation.md`,索引维护在 [README.md](README.md)。

## 工作流约定

- 个人档案库,不走 `~/CLAUDE.md` 的完整开发流程:无 Kanban work item、无 worktree、无 PR——任务归档直接 commit 到 `main` 并 push。
- 每个任务收尾时同步 [README.md](README.md) 任务索引(新增一行)。2026-08-22 曾一次性补 11 行缺失索引,属于已知返工点。
- 知识重组类任务(分散档案 → `~/Notebook/` 的 Obsidian 风格知识库)以 [2026-08-21-sunshine-notebook/](2026-08-21-sunshine-notebook/) 为既定范式:源档案原地保留(证据链),产出 MOC + 主题笔记 + wikilink;收尾验证 = wikilink 全部可解析 + gitleaks/rg 扫描 + README 补行。
- 每次 plans 更新(新增/修订任务档案)后,检查 `~/Notebook/` 对应域笔记是否需同步更新:笔记是活知识、档案是冻结证据链,知识变更应反映进笔记。

## 红线:机密信息一律不得入库

**2026-08-19 事故**:frp `auth.token` 随配置快照被提交并推送到本公开仓库,发现后从全部 git 历史清除(filter-repo + 强推)并轮换。事故档案:[2026-08-19-frp-token-redaction/](2026-08-19-frp-token-redaction/)。规则由此而来:

1. **任何 token / 密码 / 私钥 / API key / 预授权密钥(preauth key)/ 会话凭据,一律不得写入任何被 git 跟踪的文件**——包括配置实体快照、日志片段、systemd 单元(`ExecStart` 可能内嵌 token)、design.md / implementation.md 正文。没有"这是私人仓库所以可以"的例外——入库前先确认仓库可见性。
2. **配置实体入库前必须脱敏**:机密值替换为占位符(如 `__FRP_TOKEN_REDACTED__`),并在旁边注明真实值的位置(如"真实值在 `/etc/frp/frpc.toml`,0600 root")。文档里同时注明"快照已脱敏",避免后人误以为与线上逐字节一致。
3. **引用凭据文件只写路径,不贴内容**(如 `~/.bandwagon/credentials.jsonc`、`~/.cloudflare/tokens.jsonc`)。
4. **提交推送前必须扫描**:`gitleaks git .`(全历史)或至少 `gitleaks dir .`(工作区),无 leaks 才允许 commit/push。本机已装 `~/.local/bin/gitleaks`(v8.30.1);其他机器未安装时从 GitHub releases 下载单文件二进制(走 `127.0.0.1:10809` 代理)。
5. **一旦发现泄露,处置顺序**:① 轮换该机密(清历史 ≠ 安全,公开过的值必须当作已死)② filter-repo 清除全部历史并强推 ③ 修正文档中导致误判的说法 ④ 按本仓库惯例归档事故记录。
6. 主机名 / IP / 端口 / 拓扑等基础设施信息可以入库(本仓库定位即私人基础设施档案);**机密值不行**——这条界限不因仓库公私状态而改变。

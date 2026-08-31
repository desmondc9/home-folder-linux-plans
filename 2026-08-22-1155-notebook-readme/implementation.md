# ~/Notebook 纵览 README — 实施记录

日期: 2026-08-22 · 设计: [design.md](design.md)

## 任务清单

- [x] 写入 `~/Notebook/README.md`：依赖图 + 三层阅读路径 + 各域一览 + 症状索引 + 共同约定 + 仓库信息
- [x] 依赖排序：Tailscale-Headscale-DERP（组网层，地基）→ sing-box-分流网关（网关层，跑在 Exit Node 上）→ Sunshine-Moonlight-串流（应用层）；frp 标注为横切组件指向 plans 档案
- [x] 链接验证：README 内 9 个相对链接（3 目录 + 3 MOC + 3 plans 档案名）全部指向存在文件
- [x] 敏感扫描：gitleaks 0 泄漏
- [x] `~/Notebook` commit（push 待用户确认）
- [x] 本档案归档 + README 索引补行 + `~/plans` commit + push

## 产出

- `~/Notebook/README.md`（新增）
- `~/plans/2026-08-22-1155-notebook-readme/`（本档案）

## 决策与备注

- **链接形式**：README 用相对路径 markdown 链接而非 wikilink——它同时是 GitHub 仓库首页，wikilink 在 GitHub 不可点；Obsidian 中相对链接同样可点
- **README 引用本档案**：README 末尾列出四个整理任务档案指针（sunshine/singbox/tailscale/本档），形成"知识库 ↔ 整理过程"闭环
- **未动任何域内笔记**：纵览层不重复域内内容，只做索引

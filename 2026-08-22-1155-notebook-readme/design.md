# ~/Notebook 纵览 README — 设计

日期: 2026-08-22 · 状态: 已完成 · 实施记录: [implementation.md](implementation.md)

## 背景与目标

三个域知识库（Sunshine-Moonlight-串流 / sing-box-分流网关 / Tailscale-Headscale-DERP）已齐，但 vault 缺一个**纵览入口**：新打开仓库的人（或未来的自己）不知道三域的关系与阅读顺序。目标：在 `~/Notebook/README.md` 提供按**依赖关系排序**的纵览，同时作为 GitHub 仓库首页。

## 依赖排序依据

- **Tailscale-Headscale-DERP = 组网层（地基）**：节点互通、P2P 打洞、DERP 中继。无域内依赖，是另外两域的前提。
- **sing-box-分流网关 = 网关层**：跑在 tailnet 的 Exit Node 之上（TPROXY 只拦 tailscale0 入向）。依赖组网层，与 Sunshine 域互为兄弟、互不依赖。
- **Sunshine-Moonlight-串流 = 应用层**：主链路是 tailnet。依赖组网层。
- **frp** 是横切组件（备份链路），配置本体在 `~/plans/2026-08-19-1420-frp-config-archive/`，本库只引用。

## README 结构

依赖图（ASCII）→ 三层阅读路径（各附依赖说明）→ 各域一览表（MOC 相对链接，GitHub/Obsidian 双端可点）→ "该去哪里找"症状索引 → 共同约定（MOC 入口 / wikilink 歧义规避 / 证据链留 plans / 机密红线）→ 仓库与使用信息（含整理任务档案指针）。

链接形式选**相对路径**而非 wikilink：README 同时是 GitHub 仓库首页，wikilink 在 GitHub 上不可点。

## 验收标准

1. README 三层依赖排序正确，依赖图与文字一致
2. 全部相对链接指向存在的文件（三个 MOC 均存在）
3. 无敏感信息；gitleaks 通过
4. 本档案归档 + README 索引补行 + commit（Notebook / plans 各自提交）

# 实施记录

版本: agentmemory 0.9.29(npm 全局)/ opencode 1.18.25 / node v24.18.0

## 起始状态诊断

用户已跑过 `npx -y @agentmemory/agentmemory@latest`,但**并没有装完**:

- 只有 `iii` 引擎在 3111/3112,**worker 进程没在跑** → REST 全 404、viewer 3113 未监听、`Health: unknown`、`Memories: 0`
- `preferences.json` 里那 13 个 agent 只是首次运行时的多选答案,**接线并未执行**:
  `~/.claude.json` 无 MCP 块、`~/.claude/settings.json` 无 hooks、`opencode.json` 无 agentmemory
- 无 LLM provider key(选了 minimax 但没填),embedding 为 bm25-only

## - [x] 第 1 步:迁移 33 条记忆 + 修标题

先起 worker(`nohup agentmemory`),272 个函数注册完成,REST 转为 200。

第一版脚本直接把整个 md 灌进 `content`,结果 title 取到 frontmatter:`---\nname: singbox-notebook...`。
`title` 参数实测**被忽略**(POST 时传 title,返回的 title 仍取自 content 首行)。

第二版:
- 首行 = frontmatter 的 `description`(去引号),正文 = 剥掉 frontmatter 后的内容
- `type` 映射: `user|feedback` → `preference`,`project|reference` → `fact`
- `concepts` = slug 分词 + 正文里的 `[[wikilink]]`
- `files` = 源文件路径,`project` = `home-desmond-system`

清库用 `POST /agentmemory/forget {"memoryId": ...}`(先 `GET /agentmemory/export` 备份),重灌 33/33 成功。

坑:`/agentmemory/remember` 返回 **201** 不是 200,第一版脚本只判 200,导致 32 条全部成功却报 `failed=32`。

验证:`smart-search "Sunshine 串流 关屏 500"` → 首位 `sunshine-display-switch`,score 1.0。

## - [x] 第 2 步:systemd user unit 开机自启

`~/.config/systemd/user/agentmemory.service`,`WantedBy=default.target`(不碰 GUI,不需要
`graphical-session.target` 那套三件套)。

两个坑:

1. **数据目录**:`WorkingDirectory=/home/desmond` 触发了「cwd 下 `data/` 收编」逻辑,
   在家目录根建了 `~/data/{state_store.db,stream_store,iii-config.yaml}`。
   停服 → `mv` 到 `~/.local/share/agentmemory/` → `rmdir ~/data` → 重启,33 条完好。
   再用 `--data-dir /home/desmond/.local/share/agentmemory` 显式钉死,防止将来 `~/data` 重现被重新收编。
2. **nvm 路径**:`ExecStart` 写死 `v24.18.0` 的绝对路径。nvm 升级 node 后必须改 unit 并
   `daemon-reload && restart`,已在 unit 里写注释标注。

`engine-state.json` 原先 configPath 指向 npx 缓存(`~/.npm/_npx/<hash>/`,该目录 1GB),
迁移后已指向 `~/.local/share/agentmemory/iii-config.yaml`,清 npx 缓存不再影响服务。

## - [x] 第 3 步:接线 + 插件 + skills

`agentmemory connect claude-code` / `connect opencode`(先 `--dry-run` 看过 diff,自带备份写在
`~/.agentmemory/backups/`)。

副作用:opencode 的 guideline 写进 `~/.config/opencode/AGENTS.md`,而
`~/.config/opencode/AGENTS.md → ~/AGENTS.md → ~/CLAUDE.md` 是三层软链,
所以那段 `<!-- agentmemory:start -->` 围栏块(20 行)落进了 `~/CLAUDE.md` 末尾。

opencode 原生插件(22 hooks):
- `cp plugin/opencode/agentmemory-capture.ts ~/.config/opencode/plugins/`
- `cp plugin/opencode/commands/{recall,remember}.md ~/.config/opencode/commands/`
- 未写 `opencode.json` 的 `plugin` 键(理由见 spec.md 决策 4)
- 插件读的环境变量:`AGENTMEMORY_{PROJECT_NAME,SECRET,URL}` + `OPENCODE_AGENTMEMORY_DEBUG`

skills(`npx skills add rohitg00/agentmemory -g -y -a <agent> -s <skill>`):

- **`-s` 不支持逗号列表** —— `-s a,b,c` 会静默跳过安装、只打印可用列表。必须一次一个循环装。
- 装了 10 个:remember / recall / recap / handoff / forget / lesson /
  commit-context / commit-history / session-history / memory-discipline
- claude-code 和 opencode 两个 target 各装一遍(共享 `~/.agents/skills/` 存储,各 agent 目录软链过去)
- **安全提示**:skills CLI 的风险面板对每个 skill 显示 `Snyk: High Risk`(Gen: Safe / Socket: 0 alerts)。
  未深究具体条目,但这些 skill 以完整 agent 权限运行,值得复核。
- `~/.agents/skills/handoff` 被更新——查 `.skill-lock.json` 确认它**本来就是** 2026-08-27
  从 `rohitg00/agentmemory` 装的同一个 skill,不是覆盖了别的东西。`claude-handoff` 是另一个,未受影响。

## - [~] 第 4 步:本地 embedding —— 未达预期

`~/.agentmemory/.env` 里 `EMBEDDING_PROVIDER=local` 已启用,unit 里加了代理环境变量
(`HTTPS_PROXY=http://127.0.0.1:10809` + `NO_PROXY=localhost,127.0.0.1,::1`)供 HuggingFace 下模型。

`agentmemory status` 从 `bm25-only` 变成 `✓ embeddings`,**但模型从未真正加载**:

- 全盘找不到任何新下载的 `.onnx`,`~/.cache/huggingface` 停在 716K(且都是别的项目的旧文件)
- 保存新记忆、`smart-search`、`/search` 带 `mode=vector|semantic` 三条路径都试过,journal 里
  零 embedding 活动、零下载
- 代码确实实现了(`dist/index.mjs` 里 `pipeline("feature-extraction","Xenova/all-MiniLM-L6-v2",{dtype:"q8"})`,
  懒加载),`@huggingface/transformers` 这个 optional dep 也确实装了
- 结论:**状态标签会翻成「embeddings」但检索实际仍是 BM25**。没找到能触发那条懒加载路径的调用。

保留现状(设置无害,哪天那条路径被触发就会自动生效)。实测 BM25 + jieba 的中文召回已经够好:
「开机自动启动后台服务踩过什么坑」→ 首位 `systemd-user-service-gui-env`(score 1.0),查询词与
条目无任何字面重叠。

## 遗留 / 待办

- [ ] `0.0.0.0:49134`(iii 引擎 OTel WS)绑全网卡,3111/3112 只绑 127.0.0.1。
      本机有 frp 和 tailnet,建议确认它没穿出去或加防火墙规则。
- [ ] `~/.config/opencode/opencode.json` 里有**明文** ADO PAT 和 Z.AI key(本次之前就有)。
      该文件不要进任何仓库。
- [ ] 本地 embedding 见上。
- [ ] 未设 LLM provider key,所以 `AGENTMEMORY_AUTO_COMPRESS` / `CONSOLIDATION_ENABLED` /
      `GRAPH_EXTRACTION_ENABLED` 都是关的 —— 目前只有「存了什么就是什么」,没有自动压缩和固化。
- [ ] 未启用 `CLAUDE_MEMORY_BRIDGE`。它会**反向写** `~/.claude/projects/<slug>/memory/MEMORY.md`
      并受 `CLAUDE_MEMORY_LINE_BUDGET=200` 行预算约束,有覆盖手工索引的风险;
      且该路径历史上出过 silent data loss(PR #625 砍掉 `memory/` 子目录写错位置,#1134 才修回)。

## 备份位置(会话 scratchpad,非持久)

`am-export-before.json`(旧标题版)/ `am-export-33-clean.json`(当前版)/
`claude.json.bak` / `settings.json.bak` / `opencode.json.bak` / `AGENTS.md.bak` / `agentmemory.env.bak`

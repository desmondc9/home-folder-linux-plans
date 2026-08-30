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

## - [x] 第 4 步:embedding —— 经两次换型后打通

### 4a. `EMBEDDING_PROVIDER=local` 是死路

状态标签会从 `bm25-only` 翻成 `✓ embeddings`,**但模型从未加载**:全盘无新下载的 `.onnx`,
`~/.cache/huggingface` 无变化;保存记忆、`smart-search`、`/search` 带 `mode=vector|semantic`
三条路径都试过,零 embedding 活动。代码里实现是有的
(`pipeline("feature-extraction","Xenova/all-MiniLM-L6-v2",{dtype:"q8"})`,懒加载),
`@huggingface/transformers` 也装了,但没找到能触发那条懒加载路径的调用。**别信那个状态标签。**

### 4b. DeepSeek 不能做 embedding

官方文档只有 chat completions + Anthropic 格式端点,模型全是 chat/vision
(`deepseek-v4-flash`/`pro`/`flash-vision-exp`),无 embedding 模型。
GitHub issue 里直接请求 `/v1/embeddings` 得到 404,stale 关闭无官方回应。
(DeepSeek 可以做 **LLM** 侧 —— auto-compress / consolidation / 知识图谱 —— 但那是另一回事。)

### 4c. 本地 Ollama 走 OpenAI 兼容协议 —— 可行

agentmemory 的 `OpenAIEmbeddingProvider` 支持一组 **embedding 专用**环境变量,
与 LLM 侧完全隔离(不会触发 `OPENAI_API_KEY` 的 LLM 自动检测):

    EMBEDDING_PROVIDER=openai
    OPENAI_EMBEDDING_API_KEY=ollama              # 占位即可,Ollama 不校验
    OPENAI_EMBEDDING_BASE_URL=http://127.0.0.1:11434   # 不带 /v1,代码自己拼
    OPENAI_EMBEDDING_MODEL=bge-m3
    OPENAI_EMBEDDING_DIMENSIONS=1024             # 模型不在 known-models 表里时必填

注意 unit 里加了 `HTTPS_PROXY`,所以 `NO_PROXY` 必须含 `127.0.0.1`,否则 Ollama 调用会被代理吞掉。

验证方式:`journalctl -u ollama | grep '/v1/embeddings'` 看 GIN 访问日志——
这是唯一能证明链路真通的证据(agentmemory 自己的日志里没有 embedding 记录)。
冷启动约 3.3s/次,模型常驻 GPU 后约 28ms/次。

### 4d. 模型选型:mxbai-embed-large 不行,bge-m3 才行

先用了本机已有的 `mxbai-embed-large`(1024 维),链路通了但**检索质量反而比 BM25 差** ——
英文中心模型,中文向量挤成一团,「远程玩游戏画面断了连不上」返回的第一名是「个人数据脱敏」。

换 `bge-m3`(多语言,1024 维)后立竿见影。同一组零关键词重合的中文查询:

| 查询 | mxbai | bge-m3 |
|---|---|---|
| 视频播放画面卡顿风扇狂转 | ✗ | ✓ HEVC 硬解 (1.05) |
| 远程玩游戏画面断了连不上 | ✗ | ✓ sunshine-display-switch (1.05) + Moonlight (0.59) |
| 笔记本合盖后外接屏幕不亮 | ✗ | ✓ sunshine-display-switch (1.05) |
| 怎么让电脑记住我打字的习惯 | ✗ | ✗(该命中 Rime) |
| 登录不上公司的看板系统 | ✗ | ✗(该命中 ADO PAT,需一层"看板→ADO"的业务跳跃) |

**3/5 vs 0/5。** 中文场景下模型选型比"有没有向量"更决定成败。

### 4e. 换 embedding 模型必须重灌

已存记忆的向量不会自动重算,`forget` 全部 + 重跑迁移脚本(34 条约 8 秒,模型热态下 28ms/条)。

## 教训:BM25 的失效是断崖式的

中途验证犯过一个错:用「开机自动启动后台服务踩过什么坑」测出首位命中就断言"BM25 够好"。
实测该条记忆里「开机」出现 4 次、「启动」2 次 —— **那是标准的词面命中,没有证明任何语义能力**。
真正零重合的查询(「怎么让电脑记住我打字的习惯」)BM25 是 0 分,不是"差一点",是查不到。
验证检索质量必须先确认查询词与目标文档的字面重合度为零。

## 遗留 / 待办

- [ ] `0.0.0.0:49134`(iii 引擎 OTel WS)绑全网卡,3111/3112 只绑 127.0.0.1。
      本机有 frp 和 tailnet,建议确认它没穿出去或加防火墙规则。
- [ ] `~/.config/opencode/opencode.json` 里有**明文** ADO PAT 和 Z.AI key(本次之前就有)。
      该文件不要进任何仓库。
- [x] embedding 已通(Ollama + bge-m3),见第 4 步。
- [ ] 未设 LLM provider key,所以 `AGENTMEMORY_AUTO_COMPRESS` / `CONSOLIDATION_ENABLED` /
      `GRAPH_EXTRACTION_ENABLED` 都是关的 —— 目前只有「存了什么就是什么」,没有自动压缩和固化。
- [ ] 未启用 `CLAUDE_MEMORY_BRIDGE`。它会**反向写** `~/.claude/projects/<slug>/memory/MEMORY.md`
      并受 `CLAUDE_MEMORY_LINE_BUDGET=200` 行预算约束,有覆盖手工索引的风险;
      且该路径历史上出过 silent data loss(PR #625 砍掉 `memory/` 子目录写错位置,#1134 才修回)。

## 备份位置(会话 scratchpad,非持久)

`am-export-before.json`(旧标题版)/ `am-export-33-clean.json`(当前版)/
`claude.json.bak` / `settings.json.bak` / `opencode.json.bak` / `AGENTS.md.bak` / `agentmemory.env.bak`

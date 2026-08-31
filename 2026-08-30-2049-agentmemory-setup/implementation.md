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

## - [x] 第 5 步:LLM 侧接入 Kimi coding plan

### 5a. Kimi coding plan 附带一个未公开的 embedding 端点

`https://api.kimi.com/coding/v1/embeddings` 用 coding plan 的 key(`Authorization: Bearer`
和 `x-api-key` 都认)返回 200,**model 固定为 `bge_m3_embed`、1024 维**,且**无视请求里的 `model` 参数**。
官方 API reference 里没有这个端点,只写了 chat completions。

`api.moonshot.cn/v1/embeddings` 用同一把 key 是 401 —— coding plan 的 key 只在
`api.kimi.com/coding/` 域下有效,和 moonshot 平台是两套账号体系。

**没有采用**,理由不是能力而是取舍:它给的就是本地已在跑的同一个 bge-m3,
质量零提升,却带来 260ms vs 36ms(7 倍延迟)和**每条记忆全文外发**。
记录在案是因为它是无 GPU 机器上的现成后备方案。

### 5b. LLM 侧配置

    OPENAI_API_KEY=sk-kimi-...            # 见 ~/.agentmemory/.env,不入库
    OPENAI_BASE_URL=https://api.kimi.com/coding/v1
    OPENAI_MODEL=k3
    OPENAI_REASONING_EFFORT=none
    AGENTMEMORY_AUTO_COMPRESS=true
    CONSOLIDATION_ENABLED=true
    GRAPH_EXTRACTION_ENABLED=true

三个坑,缺一个都跑不起来:

1. **model id 必须是 `k3`**。`.zshrc` 里给 Claude Code 用的 `k3[1m]`(1M 上下文的环境变量写法)
   在 API 上会被拒:`Your model id does not exist, recognized as other:k3[1m]`。
2. **`reasoning_effort` 必须设 `none`**。k3 是推理模型,不设的话输出预算全烧在 thinking 上,
   `content` 返回空字符串(实测 max_tokens=32 时 32 个 token 全是 `reasoning_tokens`)。
3. **BASE_URL 必须自带 `/v1`**。`appendOpenAIRoute()` 的逻辑是:

       if (pathname === "" || pathname === "/") return `${base}/v1${route}`;
       return `${base}${route}`;

   base 带了 `/coding` 这种路径就**不再补 `/v1`**,拼成 `.../coding/chat/completions` → 404
   `resource_not_found_error`。反过来本地 Ollama 那条 base 没有路径,所以**不能**写 `/v1`。
   同一份代码,两条 base URL 的写法正好相反。

另外 unit 里有 `HTTPS_PROXY`,`NO_PROXY` 需加 `api.kimi.com,.kimi.com`(国内服务,不该绕 GFW 代理)。

### 5c. 验证 —— 又一次「flag 绿 ≠ 真在调」

四个 flag 全绿、`Provider: ✓ llm` 之后,存记忆仍然只花 75ms、`Graph: 0 nodes`。
和 embedding 那次一模一样:**状态面板不能作为验证依据**。

真正暴露问题的是显式调用 `POST /agentmemory/graph/extract`(带 `observations` 数组),
它直接把 `OpenAI API error (404)` 抛了出来 —— 这才定位到 base URL 拼接的问题。

修好后同一个调用:12 秒,`{"edgesAdded":7,"nodesAdded":7,"success":true}`,
节点类型是 `concept` / `file` / `library`。`reflect` 的 `usedFallback` 也从 `true` 变成 `false`。

`consolidate-pipeline` 能跑但按阈值跳过(`fewer than 5 summaries` / `fewer than 2 recurring patterns`),
要等会话数据积累到量才会真正产出。

### 5d. 数据外发范围变了

开 `AGENTMEMORY_AUTO_COMPRESS` 意味着**会话观测(prompt 原文、文件内容、工具输出)会发给 Kimi 做摘要**,
比 embedding 那一层的外发面大得多。embedding 仍然留在本地 Ollama,没有外发。


## - [x] 第 6 步:选型基准测试 + 一个上游缺陷

### 6a. Embedding 选型:qwen3-embedding:4b

不看模型卡宣传,用本机 34 条记忆 + 16 条"半年后会怎么问"的中文查询(刻意压低字面重合)做基准,
纯余弦相似度隔离测量,每模型单独加载(避免显存争抢污染延迟),各跑 3 轮完全确定。

| 模型 | 磁盘 | 维度 | 显存(独占) | 延迟 | R@1 | R@3 | MRR |
|---|---|---|---|---|---|---|---|
| **qwen3-embedding:4b** | 2.5G | 2560 | 4.4G 全 GPU | 42ms | **88%** | 94% | **0.91** |
| qwen3-embedding:0.6b | 639M | 1024 | 2.4G 全 GPU | 26ms | 69% | 94% | 0.81 |
| bge-m3 | 1.2G | 1024 | 664M 全 GPU | 37ms | 63% | 81% | 0.75 |
| qwen3-embedding:8b | 4.7G | 4096 | 6.7G **溢出CPU** | 88ms | 56% | 88% | 0.74 |
| nomic-embed-text | 274M | 768 | 397M | 16ms | **6%** | 19% | 0.19 |
| mxbai-embed-large | 669M | 1024 | ~670M | 37ms | **6%** | 19% | 0.17 |

结论:
- 英文中心模型(nomic / mxbai)在中文语料上是灾难级的 6%,不是"差一点"。
- **尺寸和效果不成正比**:8B 反而最差,4B 才是甜点。
- 磁盘体积 ≠ 显存占用(bge-m3 磁盘 1.2G 只占 664M;qwen3:0.6b 磁盘 639M 却占 2.4G),
  差在默认上下文窗口分配 —— 决策看显存那一列。
- qwen3 系列加官方 instruct 前缀能到 R@1 75%/R@3 100%,但 agentmemory 发原始查询、
  且文档与查询同端点无法区分,**这个上限拿不到**。对照组:同样前缀加给 bge-m3 反而
  把 R@1 从 63% 打到 44%,证明是 qwen3 特有机制而非通用增益。

**换维度必须清库重灌**:服务会拒绝启动并报
`persisted vector index has N vectors with the wrong dimension ... Loading would silently corrupt search`,
按提示用 `AGENTMEMORY_DROP_STALE_INDEX=true` 丢弃旧索引(这个保护设计得很好)。

### 6b. LLM 选型:维持 Kimi k3

从 bundle 里挖出真实的 `COMPRESSION_SYSTEM` prompt(要求严格 XML),按实际预算 `MAX_TOKENS=4096` 测:

| Provider | 模型 | schema | 延迟 | 输出 token | 问题 |
|---|---|---|---|---|---|
| cursorbridge | glm-5.2 | 100% | **5.6s** | 456 | 第三方中转,多一层信任 |
| MiniMax | MiniMax-M3 | 100% | 7.6s | 677 | 输出前带 `<think>` 散文,非纯 XML |
| **Kimi(选用)** | k3 | 100% | 13–17s | **415–423** | 无 |
| GLM | glm-5.3 | 100% | 13.5s | 1407(893 reasoning) | token 消耗最高 |
| DeepSeek | deepseek-v4-pro | 100% | 15.5s | 1076 | 无 |
| 本地 qwen2.5:7b | — | 100% | 27.6s | 302 | 与 embedding 抢显存(4.7+4.4>8G) |

- **schema 遵循度不是区分项,全部 100%**。按延迟 / 配额消耗 / 隐私三个维度选。
- **`MAX_TOKENS` 是隐藏的成败开关**:第一轮用 900 时 GLM 像"空输出"、DeepSeek 只有 2/5 标签,
  全是 `finish_reason=length` 截断 —— 这些模型 60~70% 输出预算烧在 reasoning 上。别调小它。
- 选 Kimi 的理由:415 token 是云端最省(GLM 的 1/3),auto-compress 是高频后台任务,
  配额消耗比单次延迟重要。

### 6c. 检索融合权重:维持默认 0.4/0.6

RRF 融合(`1/(60+rank)`),不是分数加权 —— 我一开始"BM25 原始分量级淹没向量"的假设是错的。

实测:BM25 权重越高越差(0.7 那组 R@3 掉到 56%);0.01/0.99 与默认 0.4/0.6 在语义查询上
差 1 条(噪声),在精确 token 查询(`AADSTS700213` / `kscreen-doctor qFatal` / `winepulse ALSA`)上
**结果完全相同**。既然没有可测量的取舍,回归官方默认。

### 6d. ⚠️ 上游缺陷:重启后向量索引静默失效

**症状**:重启后语义检索静默退化成纯 BM25,无任何报错。

**证据链**:
1. 检索时 ollama 的 `/v1/embeddings` 调用数为 0 → 查询侧从不向量化。
2. `VECTOR_WEIGHT` 从 0.6 改到 0.99 分数一字不变 → 向量腿没参与排序。
3. 闸门是 `if (this.vector && this.embeddingProvider && this.vector.size > 0)` —— `size` 为 0 就整条跳过。
4. 重灌记忆后立即检索 → 向量化正常;一旦重启 → 又归零。
5. 重灌后 DB 只涨 14KB(35×2560 维本该 1~2MB),启动日志里**从来没有** `Loaded persisted vector index`。

**根因(两个缺陷叠加)**:
- 向量索引的持久化不生效 —— 不落盘也不恢复,且应用层零报错(BM25 的持久化是正常的)。
- 唯一能重建它的 `rebuildIndex()` 被 `if (bm25Index.size === 0)` 卡住 —— 而 BM25 持久化正常,
  这个条件永远不成立。两者互相掩盖。

**排除的误判**:一度以为是我 `TimeoutStopSec=20` 太短导致收尾落盘被 SIGKILL。
放宽到 120s 后重启跑满整整 2 分钟仍然 timeout(进程根本不响应 SIGTERM),但向量依旧丢失 ——
说明不是收尾问题。DEBOUNCE_MS 只有 5s,等 90s 也没落盘。

**兜底**:`~/.local/bin/agentmemory-reindex` + unit 里的 `ExecStartPost`,
重启后自动重灌记忆源文件恢复向量索引。重灌是**幂等**的 —— 同标题同 project 走版本演化
(旧版标 `isLatest:false`),多次重灌记忆数稳定不涨。
验证:重启后 ollama 收到 36 次 embedding 调用(35 记忆 + 1 查询),向量腿存活。
**局限**:会话派生的记忆(auto-compress 产物)不在源文件里,重启后仍不可向量检索。

### 6e. 关于 R@1 的诚实说明

隔离基准里 qwen3:4b 是 R@1 88%,但走完整 agentmemory 混合检索只有 38~81%,跨轮次波动大。
原因是语料一直在变:并行的 opencode 会话持续注入观测(137→200),auto-compress 又在生成新记忆,
**几轮数字本就不可比**。稳定的结论是 **R@3 一直在 88~94%** —— 失败样本里正确答案大多排第 2。


## - [x] 第 7 步:对照官方功能清单的完整审计(2026-08-31)

### 7a. 更正:`agent-memory.dev` 就是官方站

本档案早前写"同名易混项目 jayzeng/agentmemory……域名 agent-memory.dev"——**域名归属判断错误**。
实测 `https://www.agent-memory.dev/` 明确标注 Repository = `github.com/rohitg00/agentmemory`、Author = Rohit G,
是本项目官方站。(jayzeng 那个同名项目确实存在,但站点是 `jayzeng.github.io/agentmemory`。)

### 7b. 补上 Claude Code 的 12 个 hook

审计发现 `~/.claude/settings.json` 的 `.hooks` 是 `{}`、agentmemory 出现 0 次 ——
**Claude Code 一直只有 MCP,没有自动捕获**。官方明确 Claude Code 应有 12 个 hook。
初次 `connect claude-code` 默认只写 MCP,必须显式 `--with-hooks`。

修复:`agentmemory connect claude-code --with-hooks` → 12 个事件
(SessionStart / UserPromptSubmit / PreToolUse / PostToolUse / PostToolUseFailure /
PreCompact / SubagentStart / SubagentStop / Stop / SessionEnd / Notification / TaskCompleted)。

实测验证(不是看配置,是看数据):跑 `claude -p` 无头会话 → sessions 2→5、observations 202→204,
探针会话的 cwd 正确落库,内容被捕获为 `[conversation] User prompt requests exact string echo`。

### 7c. 跨 agent 双向读取:实测通过

- **CC 读 opencode**:Claude Code 用 MCP `memory_smart_search` 取回 `sessionId=ses_faa84e61...`
  (opencode 的 `ses_*` ID 格式)的观测。
- **opencode 读 CC**:`opencode run` 调用 `agentmemory_memory_smart_search`,返回了
  `c7411741-...` 和 `6d4445ab-...`(Claude Code 的 UUID 格式会话)的观测。
- opencode 自己的 hook 同时在发(`Session status hook triggered` / `LLM parameters hook triggered` 等),
  印证 22-hook 覆盖。

### 7d. ⚠️ `import-jsonl` 不要用 —— 实测让检索质量腰斩

本机有 959 个 Claude Code JSONL transcript(918MB)从未导入。试跑 20 个文件:

| 指标 | 导入前 | 导入后 | 回滚后 |
|---|---|---|---|
| observations | 245 | 2669 | 261 |
| **R@1** | 38% | **19%** | **75%** |
| **R@3** | 94% | **44%** | **94%** |

原因:**79% 的导入观测是无标题的原始 hook 记录**(`post_tool_use` / `prompt_submit` /
`post_tool_failure`),没有 LLM 写的标题和摘要。检索「Headscale DERP 部署」返回的就是
一条 `[other] post_tool_use`。

**固化流水线救不了它们**:`consolidate-pipeline` 的 semantic 层要求「至少 5 条会话摘要」,
而摘要来自 Stop hook 的 LLM 压缩 —— 导入的历史会话从未经过那一步,永久停留在噪声态。
实测 2669 条观测下跑固化,仍然 `{"semantic":{"reason":"fewer than 5 summaries","skipped":true}}`。

**结论:全量 959 文件导入(推算 11.6 万条观测)会彻底毁掉检索,不要做。**
回滚方式:按 sessionId 调 `POST /agentmemory/forget`。

### 7e. `forget` 按 sessionId 不级联删除派生的 lesson

回滚导入会话后,`memory_lesson_recall` 仍返回 28 条 `source=consolidation` `tags=[auto-import]`
的垃圾 lesson —— 内容是从技能文档和提示词里正则抠出来的碎片
(`never frontend-design,`、`Don't skim - read every line`、`Do NOT paste the whole report.`),
`sourceIds` 全部指向已删除的会话。**lesson 会被注入 agent 上下文,污染代价比观测更高。**

清理端点是 `POST /agentmemory/lessons/delete`(注意是复数 `lessons/`;
`lesson/delete`、`lesson-delete` 都是 404)。已删除 28 条,只保留 1 条手写 lesson。

### 7f. 官方 12 项功能对照结果

| 官方功能 | 本机状态 | 证据 |
|---|---|---|
| Auto-Capture Hooks | ✅ | CC 12 个 + opencode 插件,双方实测触发 |
| MCP Tools | ✅ | worker 注册 272 个函数,两个 agent 均可调用 |
| REST Endpoints | ✅ | `api::` 触发器 130 个(与官方宣称一致) |
| Hybrid Recall | ✅ | BM25 + 向量(查询侧实测调用 ollama)+ graph |
| Provenance | ✅ | 每条带 `origin{capturedAt,channel}` + `project` |
| Auto-Consolidation | ⚠️ | 开关已开,但阈值(≥5 摘要 / ≥2 模式)长期不满足,实际很少触发 |
| Session Replay | ❌ | 见 7d,功能可用但**有害**,已弃用 |
| Knowledge Graph | ✅ | 7 nodes / 7 edges |
| Lesson Recall | ✅ | 手写 lesson 存取正常(见 7e 的污染坑) |
| Peer Sync | ⏸ | 单机部署,未启用 |
| Obsidian Export | ✅ | 导出 35 memories + 1 lesson → `~/.agentmemory/vault`(37 个 md + MOC) |
| Zero External Deps | ✅ | 单 Node 进程 + SQLite,5.1MB |

Skills:装了 10/17(有意跳过 7 个 `agentmemory-*` 自述文档,理由见 spec.md 决策 2)。

### 7g. 终态

重启后复验:`Health ✓ healthy`、Sessions 8、Observations 290、Memories 35、Graph 7/7、
Provider ✓ llm、Embeddings ✓ embeddings,向量腿存活(重启后 36 次 embedding 调用),
**R@1 69% / R@3 94%**。

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
- [x] LLM 侧已接 Kimi coding plan(k3),三个 flag 全开,见第 5 步。
- [ ] 未启用 `CLAUDE_MEMORY_BRIDGE`。它会**反向写** `~/.claude/projects/<slug>/memory/MEMORY.md`
      并受 `CLAUDE_MEMORY_LINE_BUDGET=200` 行预算约束,有覆盖手工索引的风险;
      且该路径历史上出过 silent data loss(PR #625 砍掉 `memory/` 子目录写错位置,#1134 才修回)。

## 备份位置(会话 scratchpad,非持久)

`am-export-before.json`(旧标题版)/ `am-export-33-clean.json`(当前版)/
`claude.json.bak` / `settings.json.bak` / `opencode.json.bak` / `AGENTS.md.bak` / `agentmemory.env.bak`


---

## - [x] 第 8 步:彻底卸载(2026-08-31 10:16)

**用户决定:agent memory 这类技术还不够成熟,彻底卸载。** 本档案转为「评估结论 + 反面教材」保留。

### 卸载清单(逐项已验证)

| 层 | 处理 |
|---|---|
| systemd unit | `disable --now` + 删除 unit 与 `default.target.wants` 软链 + `daemon-reload` + `reset-failed`;`list-unit-files` 现为 0 |
| 兜底脚本 | `~/.local/bin/agentmemory-{reindex,import-memories}` 已删 |
| Claude Code | `~/.claude.json` 的 MCP 块已摘除;`settings.json` 的 **12 个 hook 全部移除**(逐条过滤,保留其它 hook,结果事件数归 0) |
| opencode | `opencode.json` 的 MCP 块、`plugins/agentmemory-capture.ts`、`commands/{recall,remember}.md` 全删(空的 commands 目录一并移除) |
| skills | 10 个从 `~/.claude/skills` 与 `~/.agents/skills` 删除;14 个指向 `handoff` 的跨 agent 软链清理;`.skill-lock.json` 65→55 条 |
| `~/CLAUDE.md` | `<!-- agentmemory:start -->` 围栏块移除(665 字符) |
| npm | `npm uninstall -g @agentmemory/agentmemory`(193 个包) |
| 数据 | `~/.agentmemory`(32M)+ `~/.local/share/agentmemory`(7.9M)删除 |
| **机密** | `.env`(含 Kimi coding plan key)与 `backups/`(含 227KB `.claude.json` 快照,内有其它 MCP 密钥)**用 `shred -u` 安全清除**,而非普通删除 |
| npx 缓存 | 两个 1012M 的缓存目录 + `_npx/bin/` 垫片,共 **~2.0 GB** |
| MCP 日志 | `~/.cache/claude-cli-nodejs/*/mcp-logs-agentmemory` |

**共释放约 2.04 GB。**

### 保留的东西

- Ollama 的 embedding 模型(qwen3-embedding:4b 等)—— 用户明确要求保留,且与 agentmemory 无关。
- 本档案与 `benchmarks/` 下可复现的基准测试脚本。
- Claude Code 原生 memory(`~/.claude/projects/<slug>/memory/*.md`)—— 从来就是源头,迁移只是复制。

### 卸载后验证

- 三个配置文件 JSON 均有效;**其它 5 个 MCP(ado / web-reader / web-search-prime / zai-mcp-server / zread)在两个 agent 里都完好**,没有误删。
- 端口 3111/3112/3113/49134 全部释放,无残留进程。
- `opencode run` 实测正常返回。
- 全盘 `find -iname '*agentmemory*'` 无残留(plans 档案除外)。

### 一个操作教训

`pkill -f 'agentmemory'` 会匹配到**自己的命令行**(命令串里含该字样)从而自杀,
整条命令一件事都没做就退出(exit 144)。查进程要用括号写法 `grep -E '[a]gentmemory'`。
这条坑本机记忆里早有记录,仍然踩了。

### 结论:为什么放弃

一天的实测里,四个问题指向同一件事 —— **这类系统的"可用"与"看起来可用"之间差距很大**:

1. 向量索引重启后静默失效(持久化不恢复 + 重建被死条件卡住),语义检索退化成纯 BM25 且零报错。
2. `import-jsonl` 导入历史反而让检索质量腰斩,固化流水线因阈值永不满足而救不了。
3. 状态面板的 `✓` 不代表功能在跑 —— embedding 和 LLM 两次都是 flag 绿但实际没调用,
   只有查下游访问日志才发现。
4. auto-compress 和 consolidation 的产出本身在拉低精度(删掉那 105 条记忆后 R@1 从 38% 升到 75%),
   lesson 层还会把技能文档里的祈使句抠成"教训"注入上下文。

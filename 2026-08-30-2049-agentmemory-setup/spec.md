# agentmemory 跨 agent 记忆层落地

- 日期: 2026-08-30
- 状态: **已于 2026-08-31 彻底卸载**(结论:该类技术尚不成熟);本档案作为评估结论与反面教材保留,见 implementation.md 第 8 步

## 背景与目标

原状:Claude Code 用原生 memory(`~/.claude/projects/-home-desmond/memory/`,34 个 md + `MEMORY.md` 索引),
opencode 侧只有静态 `AGENTS.md`,无自动记忆。两边知识不互通。

目标:引入 rohitg00/agentmemory 作为**统一记忆服务器**,让 Claude Code 与 opencode
(以及将来其他 agent)读写同一份持久记忆,并把已有 33 条系统知识迁移进去。

## 方案选型

调研过的候选:

| 方案 | 结论 |
|---|---|
| opencode 官方能力 | 只有静态 `AGENTS.md` + `/init` + 会话持久化,**无自动记忆** |
| opencode-mem | 向量库 + auto-capture,但与现有纯文件记忆不同构 |
| opencode-working-memory | 搭 compaction 钩子、零额外 API 调用,markdown 落盘 |
| **rohitg00/agentmemory** | **选中**:一个服务器 + 20+ agent 适配器,MCP/REST/hooks 三层接入 |

选中理由:唯一真正做到「跨 agent 共享同一份记忆」的,且对 Claude Code 和 opencode 都有原生适配。

注意:GitHub 上有同名的 `jayzeng/agentmemory`(纯 markdown,站点 jayzeng.github.io/agentmemory)。
**`www.agent-memory.dev` 是本项目(rohitg00)的官方站,不是那个同名项目的。**

## 架构

    Claude Code (MCP)  ─┐
    opencode (22 hooks + MCP + 2 slash cmd) ─┼─► localhost:3111 ─► iii-engine + state_store.db
    其他 MCP agent      ─┘                      3112 streams / 3113 viewer / 49134 engine WS

- 存储: `~/.local/share/agentmemory/state_store.db`
- 检索: BM25(带 `@node-rs/jieba` 中文分词)+ 可选向量 + 知识图谱
- 作用域: `project` 字段只用于 consolidation/版本演化,**不过滤 recall**(已实测验证)

## 关键决策

1. **不全局设 `AGENTMEMORY_PROJECT_NAME`** —— 插件默认取 git toplevel 名,天然按仓库分组;
   又因 recall 不按 project 过滤,系统类记忆在任何仓库里都搜得到。设成全局单一值反而会把所有项目糊成一片。
2. **只装 10 个动作类 skill**,跳过 6 个 `agentmemory-*` 自述文档 + `write-agentmemory-skill`
   —— 那 7 个是讲 agentmemory 自身实现的文档,占提示词预算但日常无用。
3. **数据目录从 `~/data/` 迁到 `~/.local/share/agentmemory/`** —— 默认行为会在
   `WorkingDirectory` 下建 `data/`,放在家目录根既易误删又会跟项目的 `data/` 撞名。
4. **opencode 插件用目录自动发现,不写 `plugin` 键** —— opencode.json 原本没有 `plugin` 数组,
   现有 superpowers 靠 `~/.config/opencode/plugins/` 自动发现加载;显式写数组有关掉自动发现的风险。
5. **迁移时重写首行** —— agentmemory 的 title 取 content 前 ~60 字符,直接灌 md 会让标题变成
   frontmatter 的 `---\nname: ...`。改成「frontmatter 的 description 作首行 + 剥掉 frontmatter 的正文」。

## 验收标准

- [x] 服务健康,开机自启
- [x] Claude Code 与 opencode 均已接线
- [x] 33 条记忆迁移完成,标题可读
- [x] 中文语义检索命中正确条目
- [x] 本地 embedding 生效(Ollama + bge-m3;`EMBEDDING_PROVIDER=local` 是死路,详见 implementation.md 4a/4d)

## 后续扩展(2026-08-30 当日追加)

第 5 步:LLM 侧接入 Kimi coding plan(`k3`),开启 auto-compress / consolidation / 知识图谱。
embedding **保持在本地 Ollama**,不外发。详见 implementation.md 第 5 步。

## 最终配置(2026-08-30 定稿)

| 层 | 选型 | 依据 |
|---|---|---|
| Embedding | 本地 Ollama `qwen3-embedding:4b`(2560 维) | 本机基准 R@1 88% / MRR 0.91,显著优于 bge-m3(63%/0.75);数据不外发 |
| LLM | Kimi coding plan `k3` | schema 100%,415 token 云端最省;auto-compress 是高频任务,配额比延迟重要 |
| 检索融合 | 默认 `BM25_WEIGHT=0.4` / `VECTOR_WEIGHT=0.6` | 与向量主导(0.01/0.99)差异在噪声内,且精确 token 查询结果完全相同 |

⚠️ 依赖 `ExecStartPost` 兜底才能在重启后保住语义检索,见 implementation.md 6d。

## 参考

- https://github.com/rohitg00/agentmemory
- https://zread.ai/rohitg00/agentmemory
- https://opencode.ai/docs/rules/ , /docs/plugins/ , /docs/commands/

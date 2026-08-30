# 选型基准测试脚本(可复现)

2026-08-30 用于选定 agentmemory 的 embedding 模型和 LLM provider。
结论见上级目录 `implementation.md` 第 6 步。

| 文件 | 用途 |
|---|---|
| `queries.json` | 16 条中文查询 + 人工标注的正确答案(gold),刻意压低与目标记忆的字面重合 |
| `bench.py` | Embedding 基准:直连 Ollama 算余弦相似度,输出 R@1 / R@3 / R@5 / MRR / 延迟 |
| `llmbench.py` | LLM 基准的公共部分:内含从 agentmemory bundle 里提取的真实 `COMPRESSION_SYSTEM` prompt |
| `run1.py` | LLM 单次调用 + XML schema 打分(标签齐全度、type 是否在 enum 内、是否有前言) |
| `score.py` | 端到端打分:走 agentmemory 的 `smart-search`,而非隔离的余弦计算 |

## 怎么跑

```bash
# Embedding 对比(模型名可换)
python3 bench.py qwen3-embedding:4b bge-m3 nomic-embed-text

# qwen3 系列的 instruct 前缀变体
QPREFIX=$'Instruct: ...\nQuery: ' python3 bench.py qwen3-embedding:4b

# 端到端(需要 agentmemory 在跑,且向量索引已填充)
python3 score.py
```

## 两个坑

- **测延迟必须逐个模型隔离加载**(先 `ollama stop` 掉其它),否则显存争抢会让大模型掉到 CPU,
  数字完全失真(qwen3:8b 混跑时 88ms、独占时仍 88ms 但 33% 在 CPU;4b 混跑 164ms、独占 42ms)。
- **`score.py` 的结果会随语料漂移**:并行的 agent 会话持续注入观测、auto-compress 又在生成新记忆,
  不同时间跑出来的 R@1 不可直接比较。要对比配置就在同一时间窗口内连着跑完。

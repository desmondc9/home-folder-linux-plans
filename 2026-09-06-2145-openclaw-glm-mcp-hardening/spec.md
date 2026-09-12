# OpenClaw 默认模型切 zhipu GLM + 4 个 MCP + doctor 加固

- 日期:2026-09-06 21:45
- 环境:Kubuntu 26.04 + Wayland 笔记本(yaoshi15pro)
- 类型:本机服务配置(无 repo 代码变更,无 PR)
- 状态:已上线并验证(infer model run / mcp probe / doctor findings 4→1)

## 背景

按 `~/.zshrc` 中 ccw 的 glm provider 配置 openclaw 默认模型;参照
`~/.config/opencode/opencode.json` 的 MCP 配置装 4 个智谱 MCP;跑 doctor 交互修复。

## 调研结论(实测,非文档转述)

| 项 | 结论 |
|---|---|
| `glm-5.3[1m]`(zshrc 里的 ID) | 线上已不存在,API 报 1214 modelCode 不存在 |
| `GET /api/paas/v4/models` 官方列表 | glm-4.5/4.5-air/4.6/4.7/5/5.1/5.2/**5.3**/5.3-flash/5-turbo,无 [1m] 变体 |
| `glm-5.3` / `glm-4.7` | anthropic 兼容端点实测可用(glm-4.7 服务端别名到 glm-5.3-flash) |
| zshrc 槽位映射 | primary=glm-5.3;haiku/subagent 槽 → openclaw 的 utilityModel + subagents.model |

## 实施状态变更

### 1. 模型(models.providers.zhipu + agents.defaults)

- provider `zhipu`:baseUrl `https://open.bigmodel.cn/api/anthropic`,api anthropic-messages,
  apiKey 见密钥迁移节;模型 glm-5.3 / glm-4.7(128k ctx,32k maxTokens)
- `agents.defaults.model.primary = zhipu/glm-5.3`,fallback glm-4.7
- `utilityModel` / `subagents.model = zhipu/glm-4.7`
- 原 volcengine/ark-code-latest(一直在报 400)不再是默认;provider 配置保留未删

### 2. MCP(mcp.servers,均 probe 后保存)

| 名称 | 传输 | 说明 |
|---|---|---|
| zai-mcp-server | stdio `npx -y @z_ai/mcp-server` | Z_AI_MODE=ZHIPU,8 tools |
| web-search-prime | streamable-http | bigmodel MCP 端点,Bearer,1 tool |
| web-reader | streamable-http | 同上,1 tool |
| zread | streamable-http | 同上,3 tools |

API key 取自 opencode.json 同一智谱 key(值不录入本文档)。

### 3. doctor 修复(用户决策:改用官方 Android 客户端)

- `channels.feishu.enabled=false`、`channels.whatsapp.enabled=false`
  (消除 groupPolicy=open error 和 whatsapp 无 owner warning)
- `gateway.bind=lan`(当时决策;后被 2220 条目改为 tailnet-only + TLS)
- 8 处明文密钥 → SQLite secret store + SecretRef(`--ref-source store`):
  ZHIPU_API_KEY, BAILIAN_API_KEY, VOLCENGINE_API_KEY, GATEWAY_AUTH_TOKEN,
  MEMORY_SEARCH_API_KEY, GH_ISSUES_API_KEY, BRAVE_API_KEY, FEISHU_APP_SECRET
- `openclaw doctor --fix --non-interactive` 跑过一轮安全修复(重启网关并验证)

## 验证

- `openclaw infer model run --gateway --agent main` → provider zhipu / glm-5.3,输出正常
- `openclaw mcp probe` → 4 server 全部在线(4+8+1+1 tools)
- doctor findings 4 → 1(仅剩 bind=lan 网络可达提示,预期内)

## 遗留/已知

- REF_SHADOWED x3:bailian/volcengine/zhipu 的 config ref 被 SQLite auth profile
  (api_key mode,openclaw 原生优先级)遮蔽,运行时实际读 profile,无害冗余
- SQLite 内 auth profile key 与各 agent models.json 的明文密钥仍在(audit 标记,
  原生存储/超出静态迁移范围)
- heartbeat.agentId 警告持续存在:要心跳时
  `openclaw config set agents.defaults.heartbeat.agentId main`

# LibreChat + OpenClaw 启用 web search

**运行环境**:Bandwagon VPS(`brave-goose-1` / 104.194.83.82),Ubuntu Server 24.04。GitHub issue:desmondc9/librechat-deployment#5。

## 背景与目标
6 个端点均无搜索能力;用户实测 Kimi K3 对"现在几点/天气"给出幻觉答案(自称实时,日期却是 2025-01-27)。目标:两端都能拿到真实实时数据。

## 决策
1. **OpenClaw → MiniMax Token Plan search**(`tools.web.search.provider: minimax`, region cn):官方支持 `MINIMAX_CODE_PLAN_KEY` = 用户现有 MiniMax coding plan key,零新注册。key 放 `~/.openclaw/.env`(600)。原配置 `provider: "kimi"` 因无 moonshot 平台 key 一直 autodetect 失败(日志 `WEB_SEARCH_PROVIDER_INVALID_AUTODETECT`)。
2. **LibreChat v0.8.7 → 自托管 SearXNG**:v0.8.7 的 webSearch 只认 serper/searxng/tavily(Keenable 是 0.8.8+),无 key 唯一路径是自托管。SearXNG 作为 compose 服务仅内网可达(api 容器内 `http://searxng:8080`),settings 启用 json format;`allowedAddresses: [searxng:8080]` 放行私网目标(SSRF 保护);scraper 在 0.8.7 无 keyless 选项 → 仅 snippet 级结果。升级路径:Tavily 免费 key。

## 验收
- openclaw agent 实时问答返回真实数据 ✅(2026-09-07 星期一/白露/上海 24~29℃,finish=stop)
- api 容器内 SearXNG JSON 检索 ✅;webSearch 配置加载无 schema 错 ✅
- 用户 UI 验证:LibreChat 聊天窗 web search 开关 + 实时问答(待用户确认)

## 坑
- SearXNG 容器启动后以 uid 977 接管 `./searxng/settings.yml`(宿主属主变化,属正常)
- compose `restart api` 即重读挂载的 .env/librechat.yaml;`up -d` 不重建 bind 挂载变更

## 增补:Z.ai Web Search MCP(同日)

LibreChat 直连 z.ai 远程 MCP(`web_search_prime` 工具),作为比 SearXNG 更富的搜索路径(标题/URL/摘要/站点图标,Coding Plan 配额)。实施要点:
- v0.8.7 `mcpServers.headers` 不做 `${ENV}` 插值、`url` 做 → 用 SSE 形态把 key 放 url query(`ZAI_MCP_KEY` 在 .env)
- 坑:`title` 字段正则仅允许字母/数字/空格;一个坏块 = 整个 librechat.yaml 校验失败、api 退出
- 验收:启动日志 `Tools: web_search_prime`,api 200

## 增补二:Z.ai MCP 全家桶(同日)

补齐 web-reader / zread(SSE 形态,同 query-key 鉴权,实测 endpoint 事件返回)+ zai-mcp-server(stdio,npx 于 api 容器内,ZAI mode = 8 个视觉工具)。最终 4 server / 13 tool。坑:容器 /.npm root 属主,stdio env 需 `npm_config_cache=/tmp/npm-cache`。

# LibreChat @ Bandwagon 部署坑与解决方案手册

> 权威本:desmondc9/librechat-deployment `docs/pitfalls.md`;`~/plans` 各任务目录存档副本。
> 时间范围:2026-09-07 部署 + web search + z.ai MCP 全过程。

## 一、OpenClaw 侧

| # | 坑 | 根因 | 解法 |
|---|---|---|---|
| 1 | gateway token 发出去得 **400 空响应** | `.gateway.auth.token` 是 **SecretRef 对象**(`{source,provider,id}`),`jq -r` 把它字符串化成了 JSON 文本当 token 发 | 从 secret store 实际存储取:sqlite 只读 `~/.openclaw/state/openclaw.sqlite` 的 `secret_store_entries` 表(secret-kind 对 CLI 只写不可读) |
| 2 | 重启后立刻 curl 18789 连接拒绝 | gateway 冷启动 ~6s(node 大进程) | 验证前 sleep ≥10s,或轮询端口 |
| 3 | web search 配了 `provider: "kimi"` 却无搜索 | kimi provider 要 **Moonshot 开放平台按量 key**(`KIMI_API_KEY`),不是 coding plan key | 换 `provider: "minimax"`(直接吃 `MINIMAX_CODE_PLAN_KEY`,region=cn),key 放 `~/.openclaw/.env`(600) |

## 二、LibreChat 部署

| # | 坑 | 根因 | 解法 |
|---|---|---|---|
| 4 | upstream compose 拉的镜像是 **rc 版** | 默认镜像 `librechat-dev:latest`,与 pin 的 repo tag 脱钩 | override 里显式 `image: …librechat:v0.8.7` |
| 5 | 重启后用户全被登出 | v0.8.x 必须配 `JWT_REFRESH_SECRET`,缺省则每次启动随机生成 | .env 固定配置(生成命令见 `.env.example`) |
| 6 | mongo exit 100 / meili Permission denied / api 日志 EACCES 崩溃循环 | bind 目录首次 `up` 被 daemon 建成 **root 属主**,容器以 UID 1001 跑 | up 前建好 `data-node/ meili_data_v1.35.1/ images/ uploads/ logs/ skill/` 并 chown 1001:1001(`mkdir -p` 对已存在的 root 目录是空操作,别被骗) |
| 7 | 改了 .env / librechat.yaml 不生效 | bind 挂载变更**不触发**容器重建,`up -d` 无动作 | `docker compose restart api` 让进程重读挂载文件 |
| 8 | custom endpoint 静默消失,日志干净 | endpoint 块不完整(name/baseURL/apiKey/models 任一缺失或 models 无 default 且无 fetch)时**无告警丢弃** | 验收靠选择器可见性;排查先查块完整性 |
| 9 | mcpServers 一个坏块 → 整个 api 退出 | librechat.yaml schema 校验失败是全局 fatal | 改 yaml 前备份;改完必须盯启动日志(`Invalid custom config file`) |
| 10 | mcpServers `title` 校验失败 | 正则只允许**字母/数字/空格**,"Z.ai" 的点即炸 | title 用 "Zai Web Search" 风格 |

## 三、模型端点接入

| # | 坑 | 根因 | 解法 |
|---|---|---|---|
| 11 | Kimi coding plan 打 `api.moonshot.cn` 401 | coding plan 与 Moonshot 开放平台是**两套计费/两套端点** | anthropic base = `https://api.kimi.com/coding`;模型 `k3`/`k3-256k`/`kimi-for-coding(-highspeed)`;无 `/v1/models` → `fetch: false`;另注意其 OpenAI 端点有 coding-agent UA 白名单,通用客户端一律走 anthropic 协议 |
| 12 | MiniMax `.cn` 域名 SSL 证书过期 | 服务商问题(2026-09-07 实测) | base 换 `https://api.minimaxi.com/anthropic` |
| 13 | DeepSeek 模型名失效 | 已切 v4 命名 | `deepseek-v4-pro` / `deepseek-v4-flash`,配 `fetch: true` 自动拉取 |
| 14 | 新对话永远 "New Chat" | 自动起标题用 `current_model`:openclaw 端点=整轮 agent run 必超时;coding plan thinking 模型首 token 慢 | 见 issue #4(候选:关 titleConvo / 仅 DeepSeek 端点保留) |

## 四、Web 搜索与 MCP

| # | 坑 | 根因 | 解法 |
|---|---|---|---|
| 15 | 想配 Keenable 免 key 搜索 | **v0.8.7 没有**(0.8.8+),配了直接 schema fail | 免 key 路径 = 自托管 SearXNG(compose 服务,仅内网) |
| 16 | SearXNG 搜不出结果 | 镜像默认**禁用 json format**;且 LibreChat 有 SSRF 私网拦截 | settings.yml 开 `formats: [html, json]`;yaml 加 `allowedAddresses: [searxng:8080]`;另注:容器启动后会以 uid 977 接管配置文件,宿主属主变化属正常 |
| 17 | MCP `headers` 里的 `${KEY}` 原样发出 | v0.8.7 schema 中 **url 做 env 插值、headers 不做** | 用 z.ai 的 SSE 形态:`/sse?Authorization=${ZAI_MCP_KEY}`(web_search_prime / web_reader / zread 三个端点均实测有效) |
| 18 | stdio MCP(npx)熔断 30s | api 容器 `/.npm` 是 root 属主,UID 1001 的 npx 写缓存即死 | stdio `env` 加 `npm_config_cache: /tmp/npm-cache`(stdio 的 env 值支持 `${VAR}` 插值) |

## 环境备忘

- 运行环境:Bandwagon VPS(`brave-goose-1`),Ubuntu Server 24.04,4C/3.9G/78G
- ufw:18789 仅 loopback(默认)+ tailscale0 + `172.28.0.0/24`(override ipam 固定网段——网段固定了防火墙规则才是确定性的);在宿主机 curl 公网 IP:18789 得到响应是 **loopback 路径**,不代表公网可达
- 证书:certbot timer 自动续期;openclaw `Linger=yes` 保证 user service 开机自启
| 19 | OpenClaw 端点对话开 web search 开关报 `invalid tool configuration` | openclaw gateway 内置同名 `web_search` 工具,LibreChat 传入的客户端工具定义与之**同名冲突**(`client tool name conflict: web_search`),整轮请求被拒 | OpenClaw 端点**不开**该开关(agent 自带搜索);开关仅用于云端端点(Kimi/Z.ai/Zhipu/DeepSeek/MiniMax),Tavily 抓取在那些端点生效 |

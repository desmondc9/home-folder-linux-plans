# LibreChat @ Bandwagon VPS — 部署并接入 OpenClaw + 5 家模型 API

**运行环境**:Bandwagon VPS(`brave-goose-1` / `104.194.83.82` / IPv6 `2607:8700:5500:7bd3::2`),Ubuntu Server 24.04.4 LTS,4C / 3.9G RAM / 78G 盘(45G 可用)。

## 背景与目标

在 `librechat.signal-align.com` 部署 LibreChat(v0.8.x),作为:

1. 本机 OpenClaw gateway(agent `main`)的 Web UI
2. 手上 5 家模型 API(Kimi / Z.ai / Zhipu / DeepSeek / MiniMax coding plan & API key)的统一聊天前端

单人使用,公网可达但注册面最终关闭。

## 范围

**In**:DNS(Cloudflare 灰云 A+AAAA)、LE 证书(复用宿主 nginx + certbot)、docker compose 部署最小栈+Meili 搜索、librechat.yaml 六个 custom endpoint、openclaw gateway 开启 chatCompletions 端点并关闭微信 channel、ufw 容器网段规则、GitHub 跟踪 repo(desmondc9/librechat-deployment, private)。

**Out(记 follow-up issue)**:RAG(本机无可用 embeddings 服务,详见「RAG 暂缓」)、SSO 接入 login.signal-align.com(Ory Kratos+Hydra OIDC)、任何多用户/社交登录。

## 现状分析(2026-09-07 实测)

- 80/443 被宿主 nginx 占用,certbot 已管 `bandwagon-`/`derp.signal-align.com` 两张 LE 证书;sites-enabled 已有 derp/headscale/openclaw-tailnet 三个 vhost
- ufw:default deny incoming;18789/18790 仅放行 tailscale0 接口
- OpenClaw 2026.8.2,systemd 服务 `openclaw-gateway`,gateway 监听 `0.0.0.0:18789`(bind=lan),auth mode=token;chatCompletions 端点默认关闭;唯一 agent `main`
- docker 29.1.3 守护进程在跑,零容器;podman 存在但未用;`desmond` 不在 docker 组
- DNS:signal-align.com 在 Cloudflare(zone id `3b564a8…`),`librechat` 子域部署前不存在;盘上 `dns-token` 有 DNS Edit 权限(已验证 active)
- 内存 3.9G(可用 2.2G),swap 9G 基本未用

## 方案设计

### 架构

```
浏览器 → https://librechat.signal-align.com (Cloudflare 灰云 DNS-only)
        → 宿主 nginx vhost :80/:443 (LE 证书, SSE: proxy_buffering off, WS upgrade)
        → 127.0.0.1:3080 LibreChat api 容器 (compose project: librechat)
            ├─ mongo / meilisearch (SEARCH=true)
            ├─ → host.docker.internal:18789 OpenClaw gateway (OpenAI 协议, Bearer=gateway token)
            └─ → 5 家云端 API (Kimi/Z.ai/Zhipu/MiniMax 走 Anthropic 协议; DeepSeek 走 OpenAI 协议)
```

### 端点映射(核心决策)

| LibreChat 端点名 | 协议 | baseURL | key(.env 变量) |
|---|---|---|---|
| OpenClaw | OpenAI | `http://host.docker.internal:18789/v1` | `OPENCLAW_GATEWAY_TOKEN`(取自 openclaw.json) |
| Kimi | anthropic | `https://api.moonshot.cn/anthropic` | `KIMI_KEY` |
| Z.ai | anthropic | `https://api.z.ai/api/anthropic` | `ZAI_KEY` |
| Zhipu | anthropic | `https://open.bigmodel.cn/api/anthropic` | `ZHIPU_KEY` |
| DeepSeek | OpenAI | `https://api.deepseek.com/v1` | `DEEPSEEK_KEY` |
| MiniMax | anthropic | `https://api.minimaxi.cn/anthropic` | `MINIMAX_KEY` |

模型清单不硬编码拍脑袋:部署时用 key 实测 `GET /v1/models` 定稿写进 librechat.yaml;哪家 401/404 再换国际/国内镜像 URL。

### OpenClaw 侧变更

1. `gateway.http.endpoints.chatCompletions.enabled = true`(改 `~/.openclaw/openclaw.json`,先备份)
2. `channels["openclaw-weixin"].enabled = false`(保留账号数据)
3. `systemctl --user restart openclaw-gateway`(秒级断连窗口)
4. ufw 新增:`allow from <compose 固定网段 172.28.0.0/24> to any port 18789 proto tcp`(override 里用 ipam 固定子网,保证规则确定性)

### 安全边界(必须守住)

- chatCompletions = **operator 全权凭据**(官方文档明示)。可达面仅限:loopback(ufw 默认)、tailscale0(现有规则)、LibreChat 容器网段(新规则)。**绝不出现在任何公网监听/转发里**。
- 5 家 API key + gateway token:仅存服务器上 LibreChat `.env`(0600)与 `~/librechat-keys.env`(0600);deployment repo 只放 `.env.example` 占位;git 永不见真 key。

### 网络与证书

- Cloudflare 灰云:`A → 104.194.83.82`、`AAAA → 2607:8700:5500:7bd3::2`(与 apex 同机)
- 宿主 nginx 新 vhost:`server_name librechat.signal-align.com`,80→certbot webroot/nginx 插件签 LE→443 ssl + http2,双栈 listen;`client_max_body_size 100M`(LibreChat 上传);SSE/WS 头照抄现有 vhost 模式 + `proxy_buffering off`
- LibreChat 容器栈只绑 `127.0.0.1:3080`,不碰公网端口

### 部署资产

- `~/repos/LibreChat`:上游 clone,pin 最新 release tag,保持干净;升级 = git fetch + checkout 新 tag + compose up -d
- `~/repos/librechat-deployment`(= GitHub desmondc9/librechat-deployment, private):librechat.yaml、.env.example、docker-compose.override.yml、nginx vhost、ufw 清单、部署/升级/恢复 runbook、docs/adr/(ADR×3)、CONTEXT.md
- `~/librechat-keys.env`(0600, 用户提供 5 把 key;实施前就位)

## 关键决策与理由

1. **docker(rootful)而非 podman**:LibreChat 官方安装/更新脚本全基于 docker compose;本机 dockerd 已在跑(内存成本已沉没)。对 AGENTS.md「podman 优先」的一次有据偏离 → ADR-0001。
2. **复用宿主 nginx 而非 LibreChat 自带反代**:80/443 已被占,与现有 vhost 管理方式一致。
3. **灰云 + LE 而非橙云**:与现有证书管理一致,SSE 无 CF 缓冲风险;源站 IP 早已公开(45575 等端口)。
4. **coding plan 一律 Anthropic 协议**:Kimi 的 OpenAI 端点有 coding-agent User-Agent 白名单,LibreChat 会被拒;其余几家 Anthropic 端点均为官方推荐路径 → ADR-0003。
5. **RAG 暂缓**:用户记忆中的「vllm」实为 `models.providers.llama-cpp` 指向 `127.0.0.1:19432`,**已无进程监听**(无 vllm 二进制/容器/GPU)。无 embeddings 源则 RAG 无从谈起 → follow-up issue(复活 llama.cpp 或接云端 embedding)。
6. **注册策略**:部署时 `ALLOW_REGISTRATION=true` → 自注册 → 改 false 重启。
7. **备份**:不另建,依赖 Bandwagon 7 天自动快照;runbook 写明恢复路径(快照回滚 + compose up)。

## 性能与容量

- 负载:单用户,峰值 QPS ≈ 0(人类聊天),无容量风险。
- 内存预算:api ~500M + mongo ~200M + meili ~300M + client/nginx ~50M ≈ 1.1G,可用 2.2G + swap 9G,余量充足(升级后)。
- 磁盘:镜像 ~3G + 数据卷增量,45G 可用,无压力。
- 无自建 SQL/缓存/MQ,不触发 §12 大部分条目;唯一外部依赖为 5 家云端 API,LibreChat 侧默认有上游超时。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| gateway token 泄漏 = openclaw 全权 | 0600 文件 + .env 不进 git;ufw 边界;token 可随时换(config 内) |
| gateway 重启闪断(微信等 channel) | 微信 channel 本任务即关闭;重启窗口秒级,选在低峰 |
| LibreChat 静默丢弃不完整 endpoint 块(官方文档明示) | 部署后逐端点出现在选择器即验收项;缺失时查块完整性 |
| 某家 key 是国际/国内版本不匹配 | 401/404 时切换镜像 URL 重测 |
| certbot 签证失败(80 端口/解析未生效) | DNS 已提前建好;webroot 用现有 nginx;失败可 `--nginx` 插件重试 |

## 验收标准

1. `dig A/AAAA librechat.signal-align.com` 返回 VPS 双栈地址(灰云,非 CF IP)
2. `https://librechat.signal-align.com` 证书有效(LLE)、页面可开、双栈(v4+v6)均可达
3. 六个端点全部出现在模型选择器(不静默缺失)
4. OpenClaw 端点:发起对话 → openclaw agent `main` 真实回复(容器内 curl `host.docker.internal:18789/v1/models` 亦通)
5. 5 家云端端点各自至少一轮对话成功(或明确记录哪家 key 异常)
6. 自注册账号成功 → `ALLOW_REGISTRATION=false` 重启后注册入口消失
7. 微信 channel:`enabled=false` 后 openclaw 不再收发微信;`~/.openclaw/openclaw-weixin/` 账号数据仍在
8. 18789 从公网不可达(`curl --max-time 5 http://104.194.83.82:18789` 拒绝)
9. deployment repo 含全部配置 + runbook + ADR×3,无任何真实密钥(`rg -i 'sk-|token|secret'` 只命中占位)

## 引用

- LibreChat v0.8.x docs:quick_start / custom_endpoints / configuration
- OpenClaw docs:gateway/openai-http-api(chatCompletions、安全边界、auth matrix)
- GitHub:desmondc9/librechat-deployment(部署跟踪 issue #1、SSO issue #2、RAG issue #3)
- Kimi coding plan UA 白名单证据:kodustech/kodus-ai#1257

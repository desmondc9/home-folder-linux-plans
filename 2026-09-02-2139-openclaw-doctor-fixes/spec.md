# OpenClaw doctor 全面修复与 gateway 配置加固

- 日期: 2026-09-02
- 状态: **已完成并验证**(doctor 仅余预期内提示;follow-ups 见文末)
- 追加1: 当日晚间完成 nvm/npm-global 迁移善后 + kimi-k3 备用模型配置(见 implementation.md 追加记录)
- 追加2: 当日深夜修复 kimi-claw 官方桥接脚本安装失败(三处与 openclaw 2026.8.2 的不兼容,补丁方案见 implementation.md)

## 背景与目标

原状:`openclaw doctor` 报 gateway 服务安装失败(unsafe-permissions),随后全量体检暴露
12 项问题(明文 secret、memory search 不可用、从未备份、插件缺目录等)。

目标:修复 doctor 全部可修复项,把 gateway 调整为「LAN/tailnet 可达 + 公网不可达」的
均衡暴露状态,并按 docs.openclaw.ai/tools/kimi-search 配好 web search。

## 关键决策与理由

| 决策 | 理由 |
|---|---|
| `chmod go-w` 修 systemd 目录链(非递归、无 sudo) | 本机 `umask 002`,新建目录恒为 775 组可写,触发 openclaw 安装检查;这是环境性根因,以后新目录仍可能复现 |
| 明文 secret 迁 SQLite secret store + SecretRef | `gateway.auth.token`、llama-cpp synthetic key、KIMI_API_KEY 三项全部走 `secrets store set` + `--ref-provider default --ref-source store`,openclaw.json 不再含明文 |
| memory search 用 `provider=local` 而非 zai/kimi embedding | 实测两个 coding plan key 均无 embedding 模型(zai global 只列 glm chat 系列;Kimi API 无 embedding 模型);local = llama-cpp 插件 + EmbeddingGemma 300M Q8_0(0.3GB),按需启停,零外部依赖 |
| gateway.bind 最终回 `lan` | 用户明确要求 LAN 可达;公网侧由 ufw 默认 deny 兜底(外部实测 3 节点全部 timeout) |
| browser relay `allowLegacyAuth=false` | 用户不用 Chrome 扩展/CDP 客户端 |
| 备份目录 `~/Backups/openclaw`(700) | 归档含凭据,必须收紧权限;一次性 + 每 24h 定期 Git 备份 |
| NODE_COMPILE_CACHE 经 systemd drop-in + `~/.zshenv` | doctor 建议;`OPENCLAW_NO_RESPAWN` 有 systemd 托管故不设 |
| Kimi webSearch baseUrl 覆盖为 `https://api.kimi.com/coding/v1` | kimi.com coding plan key 对 moonshot.ai/.cn 全部 401,仅认 coding 端点(Anthropic 与 OpenAI 兼容路径均 200)——文档默认值在此 key 下不可用 |
| (晚)moonshot LLM provider 的 baseUrl 同样覆盖到 coding 端点 | 与 webSearch 同一结论的延伸;`models.mode=merge` 下只覆盖 baseUrl,kimi-k3 模型定义复用插件 catalog,无需重列 |
| (深夜)`/etc/sudoers.d/90-openclaw` 授予 desmond `NOPASSWD: ALL` | 用户明确要求 agent 具备全权系统管理能力;exec 无 TTY,sudo 要密码必失败,免密是唯一通路。风险已告知:weixin/kimi 渠道消息(含提示词注入)可间接触发 root 命令——接受该风险,靠 openclaw exec 审批链(不批 allow-always)作最后闸门;workspace AGENTS.md 写入守则:一律 `sudo -n`、失败报回不重试、破坏性 root 操作先向用户确认 |

## 最终配置快照

```
gateway.bind              = lan            # 0.0.0.0:18789;公网被 ufw 默认 deny 挡住
gateway.auth.mode         = token          # token 已在 secret store(GATEWAY_AUTH_TOKEN)
memory.search.provider    = local          # hf:ggml-org/embeddinggemma-300m-qat-q8_0
tools.web.search.provider = kimi
plugins.entries.moonshot.config.webSearch  # apiKey=SecretRef, baseUrl=api.kimi.com/coding/v1, model=kimi-k2.6
agents.entries.main.tools.alsoAllow        = ["group:messaging"]
browser.extensionRelay.allowLegacyAuth     = false
mcp.servers.web-search-prime               # zai 远程 MCP 搜索(streamable-http, Bearer 明文 header)
备份: ~/Backups/openclaw (一次性已验证 + 24h 定期)
systemd drop-in: ~/.config/systemd/user/openclaw-gateway.service.d/10-compile-cache.conf
```

### 2026-09-02 晚间追加(详见 implementation.md 追加记录)

```
agents.defaults.model.primary    = zai/glm-5.3           # 不变
agents.defaults.model.fallbacks  = ["moonshot/kimi-k3"]  # GLM 额度尽时自动切换
models.providers.moonshot.baseUrl = https://api.kimi.com/coding/v1   # coding plan key 唯一可用端点
auth profile: moonshot:manual(Kimi Coding Plan key,sqlite auth store;原始值在 ~/.zshrc 注释的 ccw 段)
openclaw/pi 全局安装已从 ~/.npm-global 迁至 nvm 目录;4 个 rc 文件的 npm-global/硬编码 nvm PATH 行已清
gateway systemd unit 已重生成指向 nvm 路径(npm-global 删除的连带修复)
```

## Web search 双通道(最终形态)

| 通道 | 用途 | 限制 |
|---|---|---|
| `web_search` 工具(kimi provider,api.kimi.com/coding) | 中文聚合搜索 | 无引用 URL |
| MCP `webSearchPrime`(api.z.ai/api/mcp/web_search_prime,复用 zai coding key) | 结构化结果 + 标题/URL/摘要/站点 | **中文查询被 1301 内容过滤**,须改英文 |

决策:保留两者互补,agent 按需选择;MCP headers 的 zod 校验只收字符串,
SecretRef 被拒(dry-run 误导性通过,实写失败),故 Authorization Bearer 为明文
(openclaw.json 0600,doctor/secrets audit 均未将其列为问题)。

## 排障知识点(复用价值)

- doctor 输出里的 `<plugin-install>` 是**脱敏占位符**(`replaceAll(installPath, '<plugin-install>')`),
  真实检查路径被隐藏;当时真实根因是 openclaw.json 残留非法键 `plugins.installs` 导致
  registry 记录过期,`doctor --fix` 可修。
- gateway 监听地址逻辑(`resolveGatewayListenHosts`):`lan`=仅 0.0.0.0;`loopback`=127.0.0.1+::1;
  `custom` 强制 IPv4——**无公开双栈监听的配置入口**。
- `openclaw configure` 交互向导可用 pty 驱动(winsize 必须非 0,否则逐字符渲染);
  `TXT:` 注入自带回车,勿重复发 ENTER。
- secrets store 中 `secret` 类条目 write-only,CLI 不可读回;sqlite 直查可读(应急)。
- Moonshot/Kimi 三套端点:`api.moonshot.ai|cn/v1`(平台 key)与 `api.kimi.com/coding`(coding plan key)
  互不认账,401 = 用错端点而非 key 无效。
- kimi-claw 官方安装脚本(claw-install.sh)与 2026.8.2 三处不兼容:注入非法 `plugins.installs` 键、
  `--dangerously-force-unsafe-install` 已退化 no-op(需 `--force`)、缺 `--accept-capabilities`;
  且脚本吞掉 install 输出,须手动重放 `openclaw plugins install <staged>` 才能看到真实报错。
  升级重跑前需重打补丁(三处改动见 implementation.md 追加记录2)。

## 验收标准(均已满足)

- `openclaw daemon install` 成功、服务 active
- `openclaw doctor`:Security 无 openclaw.json 明文项、invalid skills 消失、plugins 检查通过
- `openclaw memory status --deep`:Provider local,Indexed 2/2,Embeddings ready
- 备份归档创建且 `--verify` 通过
- web_search 实测:agent 搜「今日中国新闻」返回真实时效性答案,无 `kimi_web_search_ungrounded`
- 外部 3 节点实测 18789 全部 timeout(公网不可达),tailnet `100.64.0.4:18789` HTTP 200

## Follow-ups(未做,需用户参与)

1. `commands.ownerAllowFrom` 待填渠道用户 id:`openclaw config set commands.ownerAllowFrom '["openclaw-weixin:<id>"]'`
2. GitHub token(用户稍后自配):`openclaw config set gateway.controlUi.github.token <token>`
3. kimi web search 经 coding 端点返回**无引用 URL 的摘要**;需带引用的结构化结果时换 Brave 等 provider
4. 域名有 AAAA 记录但 gateway 仅监听 IPv4(happy-eyeballs 客户端可回落,一般无碍)

# OpenClaw 本机查漏补缺(systemAgent / 密钥收尾 / 本地 embedding / weixin 停用 / GitHub token / 备份)

- 日期:2026-09-06 23:25(grilling 起点,实施跨零点至 09-07 01:50)
- 环境:Kubuntu 26.04 + Wayland 笔记本(yaoshi15pro)
- 类型:本机服务配置(无 repo 代码变更,无 PR)
- 状态:已完成并验证(infer / mcp probe / doctor / memory 全绿)

## 背景

本机 openclaw 当晚已按 [2105 gateway-repair](../2026-09-06-2105-openclaw-gateway-repair/)、
[2145 glm-mcp-hardening](../2026-09-06-2145-openclaw-glm-mcp-hardening/)、
[2220 tailnet-tls-exposure](../2026-09-06-2220-openclaw-tailnet-tls-exposure/) 三档案配好大半
(v2026.9.2 + zhipu/glm-5.3 + 4 智谱 MCP + 8 密钥已迁 store + TLS 暴露)。本次对照
服务器档案(09-02 doctor-fixes / 09-03 github-token)grilling 两轮,定位为**查漏补缺**:
修当前报错 + 对齐服务器既定模式中本机未落地的项。

### 修复前痛点(实测)

- `AGENT_SELECTION_REQUIRED` 报错风暴(ownership=explicit + 双 agent 无 systemAgent)+ heartbeat 禁用 + dreaming cron reconcile 失败
- 明文密钥残留:`env.vars` NOTION/OLLAMA、memory search Azure `api-key` header、MCP Z_AI key + 3 Bearer
- GitHub token 缺(Control UI GitHub 项目)、备份体系缺、`browser.extensionRelay.allowLegacyAuth` 仍 true
- weixin 机器人在跑但 `commands.ownerAllowFrom` 空(任何私聊者可下命令)

## 用户决策(Round 1 / Round 2)

| Q | 决策 |
|---|---|
| Q1 任务定位 | A 查漏补缺 |
| Q2 systemAgent | 设 `agents.defaults.systemAgent.agentId=main` |
| Q3 明文密钥 | 全部迁 store;不支持 SecretRef 的面记录原因保留 |
| Q4 memory embedding | **B 切本地 llama-cpp**(与服务器对齐,弃 Azure) |
| Q5 weixin 渠道 | **B 本机停用**,渠道留服务器;本机走 Android app / Control UI 直连 |
| Q6 GitHub token + 备份 | 都配 |
| Q7 Android 配对 | 稍后自行(步骤见下) |
| Q8 plans 归档 | 补索引 + 归档 + commit |
| Q9 GitHub token 来源 | 复用本机 gh keyring 现成 token(`gh auth token` 管道,全程不回显) |

## 实施(9 项)

1. **systemAgent**:`config set agents.defaults.systemAgent.agentId main` → 热生效(dreaming cron
   立即创建)→ 重启后 `[heartbeat] started`,报错风暴消失。
2. **weixin 停用**:`plugins.entries.openclaw-weixin.enabled=false`(凭据保留可回滚);
   插件列表 15→14,channel 警告一条为预期(指向回滚方法)。
3. **allowLegacyAuth=false**(服务器 09-02 同款)。
4. **明文密钥收尾**:`env.vars.*` 与 `mcp.servers.*.env/headers` 实测**不支持 SecretRef**
   (`config set` 报 `expected string, received object`);`secrets audit --check` 亦不将这两面
   列为 plaintext(12 处标记全在 SQLite auth profile / models.json 原生存储,与服务器一致)。
   → 按服务器 09-03 既定决策:**保留 0600 明文**(openclaw.json 0600 为控制措施);试验用的
   4 个临时 store 条目已 `store rm`(终态 storeResidue=0)。
5. **llama-cpp 本地 embedding**:装 `clawhub:@openclaw/llama-cpp-provider
   --accept-capabilities`(无 installs 键注入 bug)→ pty 驱动 `openclaw configure --section model`
   (搜索 `llama` 定位 → Managed local server → **拒** 5.7G Qwen3.5 聊天模型 → embedding-only
   Yes)→ 下载 verified CPU runtime + EmbeddingGemma 314M;`memory.search={provider:local}`;
   synthetic apiKey `llama-cpp-local` 迁 store(LLAMA_CPP_API_KEY);Azure remote 块与
   MEMORY_SEARCH_API_KEY 全清。注意:本机虽有 RTX 4060,插件仍报"无 linux/x64 verified
   CUDA build"→ CPU 推理(300M embedding 可接受)。
6. **索引重建**:`memory reset --yes` 后 `memory index --force` **无 TTY 静默挂死**
   (成本确认 prompt 等 stdin,EXIT=124)→ pty 驱动跑通,163 文件 2511 chunks
   (memory 39/39·271 chunks + sessions 124/124·2238 chunks)。
7. **GitHub token**:`gh auth token | secrets store set --kind secret --value-file -
   --allow-host api.github.com --allow-host github.com GITHUB_TOKEN` +
   `config set gateway.controlUi.github.token --ref-source store --ref-id GITHUB_TOKEN`;
   读回 SecretRef(脱敏),validate 通过。
8. **备份**:先清两类阻断 symlink(3 个指向 `~/.agents/skills` 的死链技能——`skills list`
   确认不被加载;workspace/.venv 227M 二月旧物无引用)→ `backup create --verify` 通过
   (459M)→ `backup enable --repository ~/Backups/openclaw`(每 24h,目录 700)。
9. **清理**:tls cer 664→600;删含明文 NOTION key 的旧 unit `.bak`;清 openclaw.json
   `.bak.1-4` 与两个 April `.clobbered`;保留 `bak-pre-hardening-20260906` 快照 + `.last-good`。

## 验证

- `openclaw infer model run --gateway --agent main` → provider zhipu / glm-5.3,输出正常
- `openclaw mcp probe` → 4 server 全在线(zai 8 + web-search-prime 1 + web-reader 1 + zread 3 tools)
- `openclaw doctor --non-interactive` → 仅剩 1 条 bind=custom(100.64.0.1)网络可达提示
  (2220 决策的既定态,token auth 在);GitHub projects 告警消失;heartbeat 无 disabled
- memory:`Embeddings: ready`(embeddinggemma-300m-qat-q8_0),全量索引,语义检索
  「openclaw gateway TLS 配置」top1 0.889 命中 MEMORY.md
- `secrets audit --check`:plaintext=12(全为原生存储)、unresolved=0、storeResidue=0

### 已知残留(记录在案)

- `doctor.memory.dreamDiary` 在多 agent 下仍要求显式 agentId——CLI doctor 自身调用未带,
  仅 doctor 运行期间的该查询报错,不影响运行面
- workspace `notion` skill 与内置同名 precedence collision(信息性,workspace 优先,不动)
- unit PATH 含 nvm 目录 cosmetic 警告(2105 既知,`gateway install --force` 会重生成故不手改)

## Android 配对步骤(待用户执行,承接 2220 遗留)

1. OnePlus-15 连 tailnet + 安装 OpenClaw app
2. 本机 `openclaw qr` 出 full-access 配对码(**勿外传**),app 扫码;
   或手动填 `wss://openclaw.signal-align.com:18789`(Secure/TLS)
3. 本机 `openclaw devices approve <requestId>`

## 回滚

- 配置快照:`~/.openclaw/openclaw.json.bak-pre-hardening-20260906`(0600)
- weixin 回开:`config set plugins.entries.openclaw-weixin.enabled true` + 重启
- Azure embedding 回切:快照里有 `memory.search` 完整旧值(remote.baseUrl/apiKey ref/headers),
  `MEMORY_SEARCH_API_KEY` 需重录 store
- 备份停用:`openclaw backup disable`

## 参考

- 服务器档案:[2026-09-02-2139-openclaw-doctor-fixes](../2026-09-02-2139-openclaw-doctor-fixes/)、
  [2026-09-03-1025-github-token-multi-tool](../2026-09-03-1025-github-token-multi-tool/)
- 本机前置:[2026-09-06-2105](../2026-09-06-2105-openclaw-gateway-repair/)、
  [2026-09-06-2145](../2026-09-06-2145-openclaw-glm-mcp-hardening/)、
  [2026-09-06-2220](../2026-09-06-2220-openclaw-tailnet-tls-exposure/)

# 实施记录 — OpenClaw doctor 全面修复

## 任务

- [x] 修复 daemon install 权限错误(systemd 目录链 775 → 755)
- [x] 修复 doctor 12 项:非法键 / 明文 secret / memory search / 备份 / relay / skills / 工具面
- [x] gateway 暴露策略调整并外部实测(loopback → lan,公网验证不可达)
- [x] Kimi web search 配置(含 coding 端点发现)
- [x] 归档

## 反馈回路

- 权限:`stat -c '%a'` 三目录链红绿检查(775=红 / 755=绿),秒级确定性
- 服务:`openclaw daemon install` + `systemctl --user is-active` + `openclaw health`
- 终验:`openclaw doctor` 全量输出 grep WARNING 计数(修复前 3 → 修复后 1,余 1 为 bind=lan 预期提示)

## 步骤与结果

1. **权限**:`chmod go-w ~/.config ~/.config/systemd ~/.config/systemd/user`;根因 umask 002。
2. **doctor --fix**:清掉 `plugins.installs` 非法键(即 `<plugin-install>` 谜团的真身),registry 重建。
3. **secrets**:token/llama-cpp/kimi 三个 key 全部 `secrets store set --kind secret --value-file -` +
   `config set <path> --ref-provider default --ref-source store --ref-id <NAME>`;`secrets audit --check`
   openclaw.json 明文清零(sqlite 内 auth-profile zai key 属机制本身,保留)。
4. **memory search**:zai/kimi embedding 不可用(实测模型列表)→ 装 llama-cpp 插件(`--accept-capabilities`)
   → pty 驱动 `openclaw configure --section model` 选 Managed local server + embedding-only 同意
   (下载 EmbeddingGemma 0.3GB)→ `memory status --index --agent main`;注意 pty 驱动器须设 winsize 120x40。
5. **备份**:`mkdir 700 ~/Backups/openclaw`;`backup create --output ... --verify` 通过;
   `backup enable --repository ~/Backups/openclaw`(每 24h)。
6. **bind 演变**:lan →(用户要求安全)loopback(自动 127.0.0.1+::1)→(用户要求 LAN)lan;
   外部 check-host.net 3 节点实测 timeout 证明公网关闭;tailnet 100.64.0.4 HTTP 200。
7. **relay**:allowLegacyAuth=false。
8. **NODE_COMPILE_CACHE**:systemd drop-in `10-compile-cache.conf` + `~/.zshenv` export;
   `systemctl --user show -p Environment` 确认注入。
9. **skills**:time-awareness / worker-safety 两个 SKILL.md 补 YAML frontmatter description。
10. **agent 工具**:`agents.entries.main.tools.alsoAllow=["group:messaging"]`(weixin 渠道消息动作)。
11. **Kimi web search**:
    - 盲录 key 后 moonshot.ai/.cn 四种组合全 401 → 发现 `.zshrc` 注释里的 ccw 定义:
      coding plan 端点 `https://api.kimi.com/coding/`;
    - 实测 `/coding/v1/messages`(x-api-key)与 `/coding/v1/chat/completions`(Bearer)均 200;
    - 装 moonshot-provider 插件,webSearch 三件套 + `tools.web.search.provider=kimi`;
    - 端到端:agent 搜今日新闻返回真实时效答案;coding 端点无引用 URL(已知局限)。
12. **zai webSearchPrime MCP**(docs.z.ai/devpack/mcp/search-mcp-server):
    - curl 实测 MCP initialize 200 → `openclaw mcp add ... --header "Authorization=Bearer <zai key>"`;
    - `openclaw mcp probe`:1 tools;agent 实测返回结构化 URL 结果;
    - 发现中文查询 1301 内容过滤(英文正常)→ 用户决策:**保留 kimi+MCP 双通道**;
    - 未用的 ZAI_MCP_AUTH store 条目已删;moonshot 插件安装再次写入 `plugins.installs`
      非法键,doctor --fix 已二次清理(该插件安装器有此 bug,再装插件需复查)。

## 证据留存

- doctor 终态:仅 Security 区 1 条 bind=lan 提示(用户选择,token auth 在)
- `ss -tln`:`0.0.0.0:18789`(lan 模式;曾短暂 127.0.0.1+[::1])
- 外部探测:check-host.net request 49bc5dbckb66 → 3 节点 Connection timed out
- memory:`Provider: local (requested: local)` / `Indexed: 2/2 files · 11 chunks` / `Embeddings: ready`
- web search agent runId 3275a9b7(status ok,grounDED 无 ungrounded 错误)

## 清理

- pty 驱动器/临时日志已删;`/tmp/opencode/oc-schema.json` 保留(下次查 schema 可复用)
- 本记录 + spec.md 即归档,无 repo 代码变更(纯本机配置),无需 PR

---

# 追加记录(2026-09-02 晚)— nvm prefix 警告修复 → npm-global 迁移 → kimi-k3 备用模型 + gateway 服务修复

缘起:登录 shell 提示 `~/.npmrc` 的 `prefix` 与 nvm 不兼容;处理过程中牵出 openclaw
全局安装位置的迁移,以及 gateway systemd 服务指向已删除路径的连带故障;最终完成为
openclaw 配置 kimi-k3 备用模型。

## 任务

- [x] 消除 nvm prefix 警告(删 `~/.npmrc` 的 `prefix=/home/desmond/.npm-global`)
- [x] 全局包迁移:`~/.npm-global` 下的 `openclaw`、`pi`(`@earendil-works/pi-coding-agent`)重装到 nvm 目录
- [x] 清理 4 个 rc 文件(`.zprofile/.profile/.bashrc/.zshrc`)中的 `npm-global/bin` PATH 行;删除 `~/.npm-global`
- [x] 删除 rc 文件头部硬编码 nvm 版本 PATH(`v26.8.1`、`v26.3.0`,会在 nvm 加载前盖住 `nvm use` 切换)
- [x] 修复 gateway systemd 服务(ExecStart 指向已删除的 npm-global 路径;被 unsafe-permissions 拦截)
- [x] 配置 `moonshot/kimi-k3` 为 openclaw 备用模型(Kimi Coding Plan key)

## 步骤与结果

### 1. nvm / npm-global 清理

- `~/.npmrc` 仅有 `prefix=/home/desmond/.npm-global` 一行,删除后警告消失(`nvm use v26.8.1` 验证干净)。
- 迁移前确认:`~/.npm-global/bin` 有 `openclaw`、`pi` 两个命令且 PATH 引用该目录 → 先
  `npm i -g openclaw @earendil-works/pi-coding-agent` 到 nvm 目录并验证 `--version`,再删 PATH 行,
  最后 `rm -rf ~/.npm-global`。顺序不能反,否则会丢命令。
- 硬编码 nvm 版本 PATH 是历史遗留(与 npm-global PATH 同源的手工修补),4 个文件各 2 行,全部删除;
  新 zsh 验证 `node`/`npm` 由 nvm 正常接管。
- 残留(无害,未动):每个 rc 文件第 1 行 `export PATH="/usr/bin:$PATH"` 冗余。

### 2. gateway systemd 服务修复(npm-global 删除的连带后果)

- **发现**:正在运行的 gateway 进程 ExecStart 仍指向已删除的
  `~/.npm-global/lib/node_modules/openclaw/dist/index.js`;进程靠内存存活,但任何新文件解析
  (secrets.resolve 等)报 ENOENT——CLI 全程出现 `[secrets] ... unavailable` 警告。
- **修复障碍**:`openclaw gateway install --force` 被 `[unsafe-permissions]` 拦截。
  读源码(`dist/systemd-*.js`)确认检查范围 = unit 文件 + drop-in 目录链 + state 目录,
  `mode & 0o22` 即拒。逐一排查后定位:drop-in `openclaw-gateway.service.d/10-compile-cache.conf`
  为 **664 组可写**(又是 umask 002 环境性根因,见 spec.md 决策表第 1 行)。
- **修复**:`chmod go-w` 该 drop-in → `install --force` 成功(unit 重生成指向 nvm 路径,
  旧 unit 备份为 `.bak`)→ 顺手删 unit `Environment=PATH` 中残留的 npm-global 项 →
  `daemon-reload` + `openclaw gateway restart`。
- **验证**:`gateway status` 正常;`models status` 无 secrets 警告;auth store 两个 profile 可见。

### 3. openclaw 备用模型 kimi-k3

- **目的**:z.ai glm-5.3 coding plan 额度用尽时自动 fallback(配置时 `zai:default` 正处于
  rate_limit 冷却期,`models auth list` 可见 cooldown 截止时间)。
- **key 来源**:复用 `~/.zshrc` 注释中的 ccw 包装器里的 Kimi Coding Plan key(`sk-kimi-...`;
  凭据值不入库,位置仅此一处 + openclaw auth store)。
- **端点验证**:curl `https://api.kimi.com/coding/v1/chat/completions`(Bearer,model=`kimi-k3`)
  → 200。与 spec.md「排障知识点」既有结论一致:coding plan key 只认 coding 端点。
- **配置**(三步):
  1. `openclaw.json` 的 `models.providers.moonshot` 覆盖 `baseUrl=https://api.kimi.com/coding/v1`
     + kimi-k3 模型定义(reasoning、1M ctx、cost 全 0 订阅制;`models.mode=merge` 保留插件 catalog
     其余模型);
  2. `openclaw models auth paste-api-key --provider moonshot`(支持 stdin 管道喂 key)→
     profile `moonshot:manual` 落 sqlite auth store;
  3. `openclaw models fallbacks add moonshot/kimi-k3` → `agents.defaults.model.fallbacks=["moonshot/kimi-k3"]`。
- **终态**:primary `zai/glm-5.3` → fallback#1 `moonshot/kimi-k3`;`models list` 显示
  `fallback#1,configured`、auth yes。
- **端到端实测**:`openclaw agent --model moonshot/kimi-k3` 跑通;gateway 日志确认
  `provider=moonshot api=openai-completions model=kimi-k3 url=https://api.kimi.com/coding/v1/chat/completions status=200`
  流式响应正常。

## 排障知识点(增补)

- **openclaw 的 unsafe-permissions 检查范围**:unit 文件本体 + `*.service.d/` drop-in 及其目录 +
  state 目录,任何一环组/他人可写(mode & 0o22)即拒绝 install/restart。本机 umask 002 下
  手工新建的 conf/drop-in 极易踩中(继上午的 systemd 目录链之后第二次)。
- **moonshot 插件 catalog 自带 kimi-k3**(openai-completions,1M ctx);`models.mode=merge` 下
  只需在 config 里覆盖 `baseUrl` 即可把整个 provider 指向 coding 端点,无需重列模型。
- **fallback 链管理**:`openclaw models fallbacks add/list/remove/clear`,写入
  `agents.defaults.model.fallbacks`;`models set` 管 primary。
- **npm 全局目录迁移安全顺序**:列旧目录 bin → 新位置重装 → 验证命令 → 改 PATH → 删旧目录。
- **nvm 与手写 PATH 的关系**:nvm 靠 shell 加载时操作 PATH 切版本;任何在 rc 文件里硬编码的
  `nvm/versions/node/<ver>/bin` 都会在 nvm 之前压住 PATH,使 `nvm use` 看似生效实际无效。

## 证据留存(增补)

- `openclaw models status`:moonshot profile `moonshot:manual=sk-kimi-...(已脱敏显示)`;无 secrets 警告
- gateway 日志:`[model-fetch] response provider=moonshot ... model=kimi-k3 status=200` 多条
- systemd unit:ExecStart = `~/.nvm/versions/node/v26.8.1/lib/node_modules/openclaw/dist/index.js`,PATH 无 npm-global

---

# 追加记录(2026-09-02 深夜)— kimi-claw 官方桥接脚本安装失败根因与补丁方案

## 背景

用 Kimi 官方命令连接本机 openclaw:
`bash <(curl -fsSL https://cdn.kimi.com/kimi-claw/claw-install.sh) --bot-token <KIMI_BOT_TOKEN>`
报 `Installation failed! - Second script exited with code 1`,除此之外无任何有效信息。

脚本结构:`claw-install.sh` 并行跑两个子脚本——① kimiim-cli 二进制 + 3 个 skills
(kimiim/worker-safety/time-awareness,**这条路一次成功**);② kimi-claw 桥接插件
(下载 tgz → 装依赖 → `openclaw plugins install` → 写 bridge 配置 → 重启 gateway,**失败的是这条路**)。

## 任务

- [x] 拉取并通读两个子脚本,确认行为无害后复现失败
- [x] 定位真实根因(失败日志被脚本吞进 /dev/null,需手动重放)
- [x] 打补丁跑通安装,验证桥接上线

## 根因:官方脚本与 openclaw 2026.8.2 的三处叠加不兼容

全卡在 `plugins install` 一步,且脚本把该步输出重定向到 /dev/null → 表面只有一句 failed。

1. **`cleanup_legacy_plugin_config` 注入非法键**:该函数在**没有** legacy 插件时也会强行创建空的
   `plugins.installs = {}` 和 `plugins.load.paths` 并直接 `fs.writeFileSync` 写 openclaw.json;
   2026.8.2 不认 `plugins.installs`(同日上午归档的非法键,换了个注入源)→ 配置非法 →
   紧接着的 `openclaw plugins install` 被配置校验拒绝。
   时间线佐证:`.last-good`(22:34)只有 `plugins.entries`;失败 run(23:02)多出 installs+load。
2. **`--dangerously-force-unsafe-install` 已是 deprecated no-op**:非 ClawHub 本地路径安装需要
   确认,脚本的 fallback flag 在本版本不生效,正确 flag 是 `--force`。
3. **插件需要 capability consent**:还要 `--accept-capabilities`(同装 llama-cpp 时的已知模式)。

## 修复(本地补丁副本,三处改动)

- 跳过 `cleanup_legacy_plugin_config` 调用(本机无 legacy 插件,语义上本就是 no-op);
- 4 处 install fallback:`--dangerously-force-unsafe-install` → `--force --accept-capabilities`;
- **教训**:`sd` 纯文本替换 `--force` 时误伤了 `--force-cron-migration`(子串匹配),
  两处被改成 `--force --accept-capabilities-cron-migration` 后人工修回——批量替换带前缀的
  flag 名要用更长的唯一串。
- 补丁脚本为一次性产物未保留;重打方式 = 重新下载 + 上述三处改动。

跑通后脚本自动:装插件到 `~/.openclaw/extensions/kimi-claw` → enable → 写入
`plugins.entries.kimi-claw.config.bridge`(url=`wss://www.kimi.com/api-claw/bots/agent-ws`,
kimiapiHost,token)→ promptTimeoutMs=1800000 → 重启 gateway。

## 验证

- `openclaw config validate` 通过;`plugins` 键重新只剩 `entries`(安装前手工清了被注入的两个键);
- gateway active,17 个插件含 kimi-claw;
- 日志:`[kimi-bridge] [im] subscribe connected default_chat_id=...` +
  `UpdateBotMeta reported openclaw_version=2026.8.2 platform=linux` —— 桥接已上线。

## 安全注记

- bot token 以明文存于 `~/.openclaw/openclaw.json`(0600;与既有 MCP Bearer token 处置一致,
  见 spec.md 决策)。真实值位置仅此文件 + Kimi 侧后台,**本档案不记录该值**。
- 该 token 曾在排障对话中出现;若有外传风险,建议在 Kimi 侧轮换后用
  `openclaw config set plugins.entries.kimi-claw.config.bridge.token <新值>` 更新。

## 后续注意

- 官方脚本未修前,**kimi-claw 升级重跑原命令会再次失败**,需同样三处补丁;
  若官方修了 `plugins.installs` 注入与 flag 名,则只需视情况补 `--accept-capabilities`。

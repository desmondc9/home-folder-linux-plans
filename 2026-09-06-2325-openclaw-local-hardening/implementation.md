# 实施记录 — OpenClaw 本机查漏补缺

## 任务

- [x] 前置:配置快照 `openclaw.json.bak-pre-hardening-20260906` + CLI 语法核实
- [x] systemAgent=main → 报错风暴消 / heartbeat started / dreaming cron 创建
- [x] weixin 停用(enabled=false,凭据保留)
- [x] allowLegacyAuth=false
- [x] 明文密钥:SecretRef 支持面核实(env.vars/MCP 不支持)→ 保留 0600 + 记录;临时 store 条目清理
- [x] llama-cpp 插件 + configure 向导(embedding-only)→ memory.search={provider:local}
- [x] 索引重建(163 文件)+ MEMORY_SEARCH_API_KEY 删除 + synthetic key 迁 store
- [x] GitHub token:gh keyring → store(allow-host)→ controlUi.github.token SecretRef
- [x] 备份:死链/.venv 清理 → create+verify → enable 24h
- [x] 清理:tls cer 600 / 旧 unit .bak(含明文 NOTION)/ .bak 链 / April .clobbered
- [x] 终验 + 归档

## 反馈回路

- 每批:journalctl 按关键字(heartbeat/dreaming/weixin/AGENT_SELECTION)红绿检查
- 终验:`infer model run` / `mcp probe` / `doctor --non-interactive` / `memory status --deep` / `secrets audit --check`

## 变更文件表

| 文件/位置 | 变更 |
|---|---|
| `~/.openclaw/openclaw.json` | systemAgent、weixin.enabled=false、allowLegacyAuth=false、memory.search=local、llama-cpp provider+localService、controlUi.github.token ref、llama-cpp apiKey ref |
| SQLite secret store | +GITHUB_TOKEN(allow-host api.github.com/github.com)、+LLAMA_CPP_API_KEY、-MEMORY_SEARCH_API_KEY |
| `~/.openclaw/extensions/llama-cpp/` | 新装插件(2026.9.2) |
| `~/.openclaw/tools/llama.cpp/b10534/` | verified CPU llama-server |
| `~/.openclaw/models/llama.cpp/` | embeddinggemma-300m-qat-Q8_0.gguf(314M) |
| `~/Backups/openclaw/` | 700 目录 + 首个验证归档(459M)+ 24h 调度 |
| `~/.openclaw/skills/` | 删 3 个指向 ~/.agents/skills 的死链 |
| `~/.openclaw/workspace/.venv` | 删(227M,二月旧物,无引用) |
| systemd unit 目录 | 删旧 `.bak`(内含明文 NOTION key) |
| `~/.openclaw/tls/*.cer` | 664→600 |

## 排障知识点

- **`memory index` 无 TTY 静默挂死(EXIT=124)**:重建前的成本确认
  ("can incur provider cost")在等 stdin;无终端时永不超时。pty 驱动即解。区分
  "没干活"(静默退出)与"卡住"(timeout 杀)看退出码。
- **pty 驱动 configure 向导**:winsize 必须非 0(120x40);长列表用**搜索过滤**
  (直接输关键字)比数箭头可靠(本次数箭头过冲到 Chutes,靠 Back 逃生);
  Yes/No toggle 用**左右箭头**切换、Enter 确认。
- **embedding-only 路径**:先拒"下载聊天模型并设为默认"的大提案(No),才会出现
  "仅装 server + 0.3G embedding 模型、chat 模型不变"的小提案(Yes)。
- **backup 的 symlink 红线**:拒绝一切指向声明资产之外的链接(共享技能死链)与
  绝对路径目标(venv 内 python→uv)。死链判定:`openclaw skills list` 不加载即可删;
  venv 类派生物直接删(可重建)。
- **SecretRef 支持面**:`models.providers.*.apiKey`、`gateway.*.token`、channels/secrets
  等支持;`env.vars.*` 与 `mcp.servers.*.env/headers` 只收 string——迁移前先
  `config set ... --ref-source store` 试一发看报错,别直接改 JSON。
- **jq 路径含连字符**:`.mcp.servers["zai-mcp-server"]`,裸点写法会当减法解析。
- **secrets store 命令族**:`set --kind secret --value-file -`(stdin)、`rm <NAME> --yes`
  (无 delete 子命令);`audit --check` 看 plaintext/unresolved/storeResidue 三计数。
- **llama-cpp verified build 策略**:linux/x64 只发 CPU verified build,有 NVIDIA 也走
  CPU(消息原文 "No verified CUDA llama-server b10534 build is available for linux/x64");
  300M embedding CPU 推理可接受(163 文件全量索引用时约 14 分钟)。
- **doctor.memory.dreamDiary**:多 agent 环境下 CLI doctor 的该调用不继承 systemAgent
  默认,仍报要求显式 agentId——doctor 运行期间的噪音,非故障。

## 验证证据

- `infer model run --gateway --agent main` → `provider: zhipu / model: glm-5.3 / outputs: 1 / 正常`
- `mcp probe` → 4 server 全在线(8+1+1+3 tools)
- `doctor --non-interactive` → 仅 1 条 bind=custom 预期警告
- `memory status --deep` → Embeddings ready / 39/39 + 124/124 / 语义检索 0.889 命中
- `secrets audit --check` → unresolved=0, storeResidue=0
- journal:`[heartbeat] started`、dreaming cron created、weixin 不再启动

## 清理

- pty 驱动脚本(/tmp/opencode/wiz_drive.py、pty_run.py)一次性产物,留在 /tmp 自清
- 本记录 + spec.md 即归档(本仓库惯例:直接 commit main,无 PR)

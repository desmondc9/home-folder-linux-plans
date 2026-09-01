# opencode 启动缓慢 — 根因诊断与修复

- 日期: 2026-09-01
- 主机: Kubuntu 26.04 (Linux 7.0.0-30-generic), 大陆网络环境
- opencode 版本: 1.18.25 (npm `opencode-ai`, bun 单文件二进制 184MB)
- 方法: `diagnosing-bugs` skill(测量优先,禁止先猜后验)

## 背景与症状

opencode TUI 每次启动都要等约 8 秒才出现首帧。Claude Code 等其他 CLI 无此现象。

## 结论(先说答案)

**启动耗时的 83% 来自 opencode 的 Azure provider 探测:它在每次启动时同步阻塞地
执行 `az cognitiveservices account list`。** 该命令在本机需 ~5.7s(Azure CLI 要拉起
一个完整 Python 解释器,并从 GFW 后访问 Azure 管理端点)。

| 场景 | TTFD(opencode 自带 `OPENCODE_SHOW_TTFD`) |
|---|---|
| 修复前 | 8158 ms / 8163 ms |
| 修复后 | 2473 ms / 2617 ms |

净收益 **−5.6s / 3.3x**。剩余 2.5s 是 opencode 自身 bun 运行时 + instance bootstrap,
非本机配置所致(见下「已排除」)。

## 触发条件(来自二进制内打包的源码)

```js
Z = readFile($AZURE_CONFIG_DIR ?? ~/.azure/azureProfile.json)
      .then(X => X.subscriptions.length > 0).catch(() => false)

Q = (!process.env.AZURE_RESOURCE_NAME && !process.env.AZURE_RESOURCE_GROUP && Z)
      ? await az(["cognitiveservices","account","list","--output","json","--only-show-errors"])
      : []
```

即:**只要 `~/.azure/azureProfile.json` 里有 ≥1 个订阅(登录过 Azure CLI),就会跑这次
探测**,除非 `AZURE_RESOURCE_NAME` 或 `AZURE_RESOURCE_GROUP` 已设置。

## 关键陷阱:`disabled_providers` 无效

直觉上应该用 opencode 配置里的 `disabled_providers: ["azure", ...]` 关掉。**实测无效**:

| 方案 | 实测 server-ready 耗时 |
|---|---|
| 对照(不改) | 6.28 s |
| `disabled_providers: ["azure","azure-cognitive-services"]` | 6.73 s(**无改善**) |
| `AZURE_RESOURCE_NAME=<sentinel>` | **1.13 s** |

原因在打包源码里可见:`x = yield* J.list()`(枚举 provider,此处已付出 az 调用代价)
发生在 `disabled_providers` 过滤**之前**。该配置项只过滤最终列表,不阻止 loader 执行。
**以后遇到同类问题不要再试这个键。**

## 已排除的假设(有实测,勿重复走弯路)

| 假设 | 判定 | 证据 |
|---|---|---|
| 526MB `opencode.db` 打开/迁移慢 | **否** | 换成全新 250KB DB(仅 symlink 复用 auth.json),耗时不变(5.65s 窗口) |
| models.dev 目录(4.4MB `models.json`)阻塞下载 | **否** | 把代理指向立即 refuse 的端口,5.2s 窗口完全不变;源码显示该刷新是 `forkScoped` + 每 60 分钟后台重复,读缓存优先 |
| 外部插件(superpowers) | **否** | `--pure` 与完整启动 TTFD 差异在噪声内(2496 vs 2534 ms) |
| 5 个 MCP server 拖慢首帧 | **否** | 删掉 `mcp` 段后 TTFD 2496ms,与保留时相同 — MCP 是异步 spawn,不阻塞首帧 |
| 工作目录大小/仓库扫描 | **否** | 空目录启动与 `$HOME` 启动同为 ~8s |

## 方案

在 `~/.local/bin/opencode` 放一个 wrapper,仅为 opencode 进程注入
`AZURE_RESOURCE_NAME=opencode-skip-az-probe`(若用户未自行设置),然后 exec 真实二进制。

选 wrapper 而非写进 `~/.zshrc` 的理由:该变量不污染全局环境(系统其他位置未引用过它,
已用 rg 确认),不影响 `az` CLI 本身,回滚只需 `rm ~/.local/bin/opencode`。
`~/.local/bin` 在 PATH 第 3 位,先于 nvm 的第 10 位,故 wrapper 生效。

风险:若将来真的要用 opencode 的 Azure provider,需删除 wrapper,或把该变量改成真实的
Azure OpenAI 资源名。当前无风险 —— 全部历史会话的 provider 使用统计为
zhipuai-coding-plan(4092)、cursor-bridge(15)、zai(16)、zai-coding-plan(3),
**Azure provider 从未被使用过**。

## 验收标准

- [x] TTFD 从 ~8.2s 降到 ~2.5s(opencode 自带计数器,重复 2 次)
- [x] `strace -e trace=execve` 启动全程 `cognitiveservices` 出现次数 = 0
- [x] `az account show` 仍正常工作
- [x] `AZURE_RESOURCE_NAME` 未泄漏到用户 shell
- [x] `opencode --version` 经 wrapper 正常返回 1.18.25

## 参考

- 反馈回路脚本:见 implementation.md「反馈回路」一节
- 上游可改进点:该 az 探测应当加超时/并发化/受 `disabled_providers` 约束

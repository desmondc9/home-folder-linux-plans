# WSL PATH Windows 污染根治 — 实施记录

对应设计:[spec.md](spec.md) · 日期:2026-09-26 09:48

## 任务清单

- [x] 确认环境:WSL2(kernel 6.18.33.2-microsoft-standard-WSL2)+ zsh + nvm v26.10.0
- [x] (前置任务)MCP 配置迁移:解析 `~/.config/opencode/opencode.jsonc` 的 `mcp` 段,转换 4 个服务器写入 `~/.pi/agent/mcp.json`(格式映射见变更文件表),`jq` 校验通过
- [x] Phase 1 取证:PATH 逐条分析(50 条含 34 条 /mnt)、shell 配置文件排除法、双侧 npm cache mtime 对比、Windows npx shim 源码分析、Windows 侧 .pi 目录核查
- [x] Phase 3 假设验证:模拟无 nvm 的 PATH,实证 `npm`/`npx` 落到 `/mnt/d/Apps/nodejs/` Windows shim
- [x] 撰写新 `/etc/wsl.conf`(保留原 `[boot]`/`[user]` 段 + 新增 `[interop]`),暂存 `~/wsl.conf.new`
- [x] 编写 `~/verify-wsl-path.sh` 五项自检脚本
- [ ] 用户执行:`sudo cp ~/wsl.conf.new /etc/wsl.conf`
- [ ] 用户执行(Windows 侧):`wsl --shutdown`,重开 WSL 终端
- [ ] 重启后验证:`bash ~/verify-wsl-path.sh` 全绿
- [ ] 端到端验证:pi 里 `/mcp` 连接 zai-mcp-server,确认进程为 WSL node

## 变更文件表

| 文件/对象 | 变更 |
|---|---|
| `~/.pi/agent/mcp.json` | 新增(pi 全局 MCP 配置)。OpenCode→pi 格式映射:`command` 数组拆为 `command`+`args`;stdio 的 `environment`→`env`;remote 的 `type`+`url`+`headers`→直接 `url`+`headers`。4 个服务器:zai-mcp-server(stdio)+ web-search-prime / web-reader / zread(z.ai 远程)。**含 API key,永不入本仓库** |
| `~/wsl.conf.new` | 新增(暂存)。`[boot]`/`[user]` 原样 + `[interop] enabled=true` + `appendWindowsPath=false` |
| `/etc/wsl.conf` | 待变更(`sudo cp ~/wsl.conf.new /etc/wsl.conf`,内容同上) |
| `~/verify-wsl-path.sh` | 新增。五项自检:无 /mnt PATH、pi 唯一、node/npm/npx=nvm、非交互 npx 干净失败、全路径 .exe 互操作可用 |
| `~/plans/2026-09-26-0948-wsl-path-windows-contamination/` | 新增(本档案) |

## 验证

- `jq . ~/.pi/agent/mcp.json` 通过(迁移时)
- `cat /etc/wsl.conf` 确认 sudo 写入失败时未被半写(agent 无免密 sudo,`sudo -n` 探测返回 `interactive authentication is required`,文件保持原样)
- 五项自检与端到端验证待 `wsl --shutdown` 重启后执行(见 spec.md 验收标准)

## 排查时间线(取证用)

| 时间(2026-09-26) | 事件 |
|---|---|
| 08:44 | Windows 侧 `C:\Users\Desmond\.pi\agent\{bin,install}` mtime(Windows 版 pi 存在但**无 mcp.json**) |
| 08:49 | WSL 侧 pi-mcp-adapter 安装(`~/.pi/agent/npm` mtime) |
| 08:50–08:52 | WSL pi 会话(用户 `mcp({connect})` zai-mcp-server 失败;`~/.pi/agent/sessions/--home-desmond--/*.jsonl`) |
| 09:00:32 | Windows `AppData\Local\npm-cache\_npx/aefbec131226782c`(@z_ai/mcp-server)被 Windows node.exe 写入 —— 串台实锤 |
| 09:02 起 | 本会话 systematic-debugging 调查 |
| 09:48 | 修复暂存 + 本档案 |

## 备注 / 可迁移经验

- **`appendWindowsPath` 默认 true 是 WSL↔Windows 工具串台的总根源**;"调整 PATH 顺序"防不住"WSL 没装的工具"(如非交互进程视角下的 node),正确粒度是 `[interop] appendWindowsPath=false` 整段移除,`enabled=true` 保留全路径互操作。
- **Node.js Windows 安装器的 `npm`/`npx` sh shim 自带 WSL 分支**(检测 `uname = 'Linux' && type wslpath`):从 WSL 误触**不会报错**,而是静默换用 Windows node.exe 并写 Windows npm cache —— 最危险的一类失败,表面"命令成功"实则跨了 OS。凡是 WSL 里 `which npm` 出现第二个 `/mnt/*/nodejs/npm` 条目的,这个雷就已埋下。
- **双侧 npm cache 的 `_npx` 哈希目录 mtime 对比**是判定"这个包到底被哪边的 node 跑了"的廉价取证手段:哈希目录名由包 spec 决定、两侧同名,mtime 落在当天即当天所为。
- **nvm 只经 `.zshrc` 交互加载**:agent/服务 spawn 的非交互子进程没有 `~/.nvm/.../bin`。关掉 PATH 追加后,最坏情况从"静默串台"收敛为 ENOENT 干净失败;日后 systemd 服务需要 node 时再显式 source nvm 或装系统级 node。
- **`wsl.conf` 改动须 `wsl --shutdown` 才生效**,且 WSL 内的 agent 不能自己执行(等于自杀,连带杀掉 VS Code Remote 与进行中的会话)——此类变更交宿主侧执行,暂存件放 `~/` 而非 `/tmp`(后者重启后可能被清)。
- **pi 的 MCP stdio 链路依赖 pi 进程的 PATH**(`pi-mcp-adapter/npx-resolver.ts` 经 `crossSpawn("npm")` 解析 npx):诊断"pi 某 MCP 连不上"时,先查 pi 进程环境的 PATH 解析,再看 MCP 配置本身。
- 本仓库公开:API key 类秘密只留在 `~/.pi/agent/mcp.json` 等配置文件,档案文档中一律不引用原文(参见 [../2026-08-19-1528-frp-token-redaction/](../2026-08-19-1528-frp-token-redaction/))。

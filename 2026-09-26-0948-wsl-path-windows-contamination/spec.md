# WSL PATH Windows 污染根治(appendWindowsPath=false)

日期:2026-09-26 09:48 · 状态:**待生效**(配置已暂存 `~/wsl.conf.new`,待用户 `sudo cp` + `wsl --shutdown` 重启后验证) · 实施记录:[implementation.md](implementation.md)
- 环境:Windows 11 宿主 + WSL2 Ubuntu(kernel `6.18.33.2-microsoft-standard-WSL2`),zsh + nvm(node v26.10.0)
- 起因:pi(`~/.local/bin/pi`)的 MCP 服务器 `zai-mcp-server` 无法连接,用户怀疑与之前 cursor-agent 一样串到了 Windows 侧 NodeJS

## 背景与目标

- 2026-09-26 早间把 OpenCode 的 4 个 MCP 服务器迁移到 pi(`~/.pi/agent/mcp.json`:zai-mcp-server 为 stdio 本地服务器,`npx -y @z_ai/mcp-server`;另三个为 z.ai 远程端点)。随后 pi 里 zai-mcp-server 连不上。
- 经 systematic-debugging 四阶段调查,确认这不是 pi 或 MCP 配置的问题,而是 **WSL PATH 被 Windows PATH 整段污染** + **WSL 侧 node 仅经 nvm 在交互 shell 加载** 两个因素叠加,导致非交互进程的 `npx` 静默落到 Windows shim,进而由 **Windows node.exe** 接管执行 —— 与当年 cursor-agent 是同一机制。
- **目标**:根治 PATH 污染(`appendWindowsPath=false`),保证 WSL 内一律使用 Ubuntu 侧工具链;失败模式从"静默跨 OS 串台"收敛为"干净报 command not found"。

## 现状分析(证据链)

| # | 证据 | 结论 |
|---|---|---|
| 1 | `~/.pi/agent/mcp.json` 配置无误;pi 启动器 `~/.local/bin/pi` → WSL node v26.10.0;pi 会话日志无 zai 报错(用户 `mcp({connect})` 失败) | 配置与 pi 本身不是根因 |
| 2 | WSL PATH 共 50 条,其中 **34 条为 `/mnt/c`、`/mnt/d`** Windows 路径,且 system32/dotnet 等重复两份,含死路径 `/mnt/d/App/*`(Windows 侧实际是 `D:\Apps`,单复数并存) | Windows PATH 被整段追加,且 Windows 侧 PATH 本身有历史残留 |
| 3 | `.zshrc`/`.zprofile`/`.zshenv`/`.profile`/`.bashrc`/`/etc/profile.d` 均无任何 `/mnt` 手工添加 | 污染全部来自 WSL init 的 `appendWindowsPath`(默认 true;`/etc/wsl.conf` 无 `[interop]` 段) |
| 4 | 模拟实验:PATH 去掉 nvm 目录(保留 /mnt)后,`npm`/`npx` 解析到 `/mnt/d/Apps/nodejs//npm`、`/mnt/d/Apps/nodejs//npx` | nvm 只在交互 shell 加载;非交互进程(spawn 的子进程)必落 Windows shim |
| 5 | `/mnt/d/Apps/nodejs/npx` 是 Node.js Windows 安装器的 cygwin/mingw sh shim,内含 `uname = 'Linux' && type wslpath` 的 **WSL 检测分支** | 误触不会报错,而是静默换用 Windows node.exe + Windows npm cache(`AppData\Local\npm-cache`) |
| 6 | 双侧 npm cache 取证:WSL `~/.npm/_npx` 有 `@z_ai/mcp-server@0.1.5`(旧);Windows `AppData\Local\npm-cache\_npx/aefbec131226782c`(同名哈希目录)**mtime = 2026-09-26 09:00:32(当天)** | 当天确有真 Windows node.exe 跑了 `@z_ai/mcp-server` —— 串台实锤,非历史残留 |
| 7 | Windows 侧 `C:\Users\Desmond\.pi\agent\` 无 `mcp.json` | Windows 版 pi 不是肇事者;Windows npm cache 的写入来自其他 Windows 应用(候选:仍配着该 MCP 的 cursor-agent 等) |
| 8 | `~/.vscode-server/bin/*/bin/remote-cli/code` 存在 | VS Code 集成终端的 `code` 不依赖 Windows PATH,关闭追加后不受影响 |

## 方案

`/etc/wsl.conf` 增加(其余段落原样保留):

```ini
[interop]
enabled=true            # 保留 .exe 互操作:全路径仍可运行 Windows 程序
appendWindowsPath=false # 不再把 Windows PATH 追加进 WSL —— 根治串台
```

配套:`~/verify-wsl-path.sh` 五项自检(重启后验证用);暂存文件 `~/wsl.conf.new`。

不采用"调整顺序把 Linux 路径放前面":Windows 路径本就在末尾,顺序无法防御"WSL 没装的工具"(node/npm 只有 nvm 一份且非交互不可见),唯一正确的粒度是整段移除。

## 范围

**In scope:**
- `/etc/wsl.conf` 增加 `[interop]` 段(经 `~/wsl.conf.new` 暂存,用户 sudo 应用)
- 验证脚本 `~/verify-wsl-path.sh`
- 顺带完成的前置任务记录:MCP 配置 OpenCode → pi 迁移(`~/.pi/agent/mcp.json`)

**Out of scope:**
- Windows 侧仍配着 zai MCP 的应用(疑似 cursor-agent)—— 在 Windows node 下跑,与 WSL 无害无关;要停用需去 Windows 侧应用删配置
- nvm 仅交互加载导致的"非交互进程无 node"问题(关追加后表现为干净失败,属独立问题;若日后 systemd 服务需要 node,再显式 source nvm 或装系统级 node)
- 裸名 `.exe` 调用习惯的迁移(用全路径替代)

## 验收标准

1. `bash ~/verify-wsl-path.sh` 全绿:
   - PATH 无任何 `/mnt/` 条目
   - `pi` 唯一解析到 `~/.local/bin/pi`
   - 交互 shell 的 node/npm/npx 均为 nvm 版
   - 非交互最小 PATH 下 `command -v npx` 为空(干净失败,不落 Windows)
   - 全路径 `/mnt/c/Windows/System32/cmd.exe` 互操作仍可用
2. 重启后 pi 中 `/mcp` 连接 zai-mcp-server 成功,进程为 WSL node(`ps aux | grep z_ai` 可见 `~/.nvm/.../node` 路径)
3. Windows 侧 `AppData\Local\npm-cache\_npx` 不再出现新的 WSL 触发的写入(mtime 不随 WSL 内 pi 操作变化)

## 风险与缓解

- **裸名 `.exe`(`explorer.exe .`、`clip.exe` 等)失效** → `enabled=true` 保留互操作,全路径可用;高频命令可后续按需加 alias
- **普通 WSL 终端(非 VS Code)的 `code` 失效** → VS Code 集成终端不受影响(remote-cli);普通终端用全路径 `/mnt/d/Apps/Microsoft VS Code/bin/code`
- **`wsl --shutdown` 终止所有 WSL 会话**(含 VS Code Remote、进行中的 agent 会话)→ 由用户择机执行;重启后 `/tmp` 可能被清,暂存件已放 `~/wsl.conf.new`
- **已开会话的 PATH 仍是旧值** → 配置只对新启动的 WSL 实例生效,重启前不具测试条件

## 遗留(待用户执行)

- [ ] `sudo cp ~/wsl.conf.new /etc/wsl.conf`(agent 无免密 sudo,须用户交互执行)
- [ ] Windows 侧 `wsl --shutdown` + 重开终端
- [ ] `bash ~/verify-wsl-path.sh` 五项全绿
- [ ] pi 重连 zai-mcp-server 验证(验收标准 2/3)

## 参考

- pi MCP 配置来源:`~/.config/opencode/opencode.jsonc`(`mcp` 段)→ 迁移映射见 [implementation.md](implementation.md) 变更文件表
- pi-mcp-adapter 的 stdio spawn 链路:`npx-resolver.ts` 经 `crossSpawn("npm")` 按 pi 进程 PATH 解析 —— PATH 污染直接影响该链路
- `~/.pi/agent/mcp.json` 含 Z.AI API key,**该文件不入本仓库**(本仓库公开,参见 [../2026-08-19-1528-frp-token-redaction/](../2026-08-19-1528-frp-token-redaction/) 的事故教训)

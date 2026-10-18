# WSL `code` 命令失效修复(appendWindowsPath=false 的副作用)

日期:2026-10-18 10:51 · 状态:**已完成并验证**(当日修复、`code --version` 实测通过) · 实施记录:[implementation.md](implementation.md)
- 环境:Windows 宿主 + WSL2 Ubuntu(kernel `6.18.54.1-microsoft-standard-WSL2`),zsh
- 前置:2026-09-26 起 `/etc/wsl.conf` 设 `appendWindowsPath=false`(见 [2026-09-26-0948-wsl-path-windows-contamination](../2026-09-26-0948-wsl-path-windows-contamination/spec.md))
- 起因:独立终端中 `code <目录/文件>` 无法使用,用户报障

## 现象

任意 shell 中执行 `code .` / `code notes.md` 报 command not found(`command -v code` exit 1)。

## 诊断证据链

| # | 证据 | 结论 |
|---|---|---|
| 1 | `command -v code` exit 1;`~/.local/bin/code`、`/usr/local/bin/code` 均不存在 | WSL 侧从未有过 `code` 入口脚本 |
| 2 | `/etc/wsl.conf` `[interop] enabled=true, appendWindowsPath=false`;`/mnt/c`、`/mnt/d` 已挂载 | 互操作未关,但 Windows PATH 不再追加 → Windows 侧 `code` 必然不可见 |
| 3 | `~/.vscode-server` 存在 | WSL 扩展装过、能正常连接,缺的只是入口命令 |
| 4 | C 盘默认位置(`Program Files`、`AppData\Local\Programs`)无 VS Code;`/mnt/c/Users/` 下用户为 `Desmond` | 安装位置非默认,不能按常规定位 |
| 5 | 全路径 `/mnt/c/Windows/System32/cmd.exe /c "where code"` → `d:\Apps\Microsoft VS Code\bin\code{,.cmd}` | VS Code 实际装在 D 盘自定义路径 |
| 6 | `/mnt/d/Apps/Microsoft VS Code/bin/code` 为 sh 脚本(`#!/usr/bin/env sh`,VS Code 官方为类 Unix/WSL 环境提供) | 可直接从 WSL 桥接调用,无需 .exe 互操作转换 |

## 根因

`appendWindowsPath=false` + VS Code 装在 Windows 自定义路径 `d:\Apps\Microsoft VS Code`,两者叠加:

- Windows PATH(含 `d:\Apps\Microsoft VS Code\bin`)不再进 WSL PATH;
- WSL 扩展正常连接后本会在 `~/.local/bin/` 注入 `code` 脚本,但该文件不存在(推测 `.local/bin` 清理或注入时机未满足);
- 于是 WSL 侧 `code` 彻底失效。

**对 09-26 条目证据 #8 的修正**:该条曾以 `~/.vscode-server/bin/*/bin/remote-cli/code` 存在为由,判定关闭追加后 `code` 不受影响——该结论**仅在 VS Code 集成终端内成立**(集成终端会把 remote-cli 临时前置到 PATH),独立终端(zsh 直接打开)中没有这条路径,`code` 依然失效。本次即其边界条件暴露。

## 方案

在 `~/.local/bin/code` 创建转发脚本,单命令桥接到 Windows 侧官方 sh 脚本:

```sh
#!/bin/sh
exec "/mnt/d/Apps/Microsoft VS Code/bin/code" "$@"
```

选型理由:
- **不改回 `appendWindowsPath=true`**:那是 09-26 为根治 node/npm 跨 OS 串台的有意决策,重开会复发旧问题;
- **不用 .exe 直连**(`code.cmd`/`Code.exe`):Windows 侧 `bin/code` 本就是官方为 WSL 准备的 sh 脚本,参数/路径/wslpath 处理齐全;
- **粒度最小**:只放行 `code` 一个命令进 Ubuntu,其余 Windows 工具依旧隔离,与既有决策意图一致。

## 修复实施与验证

见 [implementation.md](implementation.md)。要点:`chmod +x` 后 `code --version` 输出 `1.142.0` 通过;`~/.local/bin` 已在 PATH,无需改配置、无需重开终端。

## 维护提示

- 若 VS Code 更换安装位置(如挪回 C 盘),改 `~/.local/bin/code` 内路径即可;
- 若 VS Code 大版本升级后行为异常,先 `head` 确认 `/mnt/d/Apps/Microsoft VS Code/bin/code` 仍为 sh 脚本;
- 该 wrapper 与集成终端的 remote-cli `code` 不冲突:集成终端内 remote-cli 优先(PATH 更靠前),独立终端用 wrapper,最终都落到同一 `~/.vscode-server`。

## 范围

- ✅ 修复独立终端 `code` 命令(已完成)
- ❌ 不改 `/etc/wsl.conf`(保持 09-26 决策)
- ❌ 不处理其他 Windows 命令的按需桥接(哪个失效再单独立项,同模式处理)

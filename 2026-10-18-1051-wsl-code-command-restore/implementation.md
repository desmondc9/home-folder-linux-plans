# 实施记录:WSL `code` 命令失效修复

日期:2026-10-18 · 关联 [spec.md](spec.md) · 状态:已完成并验证

## 执行步骤

1. **诊断**(只读):
   - `command -v code` → exit 1;`ls ~/.local/bin/code /usr/local/bin/code` → 不存在
   - `cat /etc/wsl.conf` → `[interop] enabled=true / appendWindowsPath=false`(09-26 决策,保留)
   - `ls -d ~/.vscode-server` → 存在(WSL 扩展服务端已装)
   - `/mnt/c/Windows/System32/cmd.exe /c "where code"` → `d:\Apps\Microsoft VS Code\bin\code{,.cmd}`
   - `file "/mnt/d/Apps/Microsoft VS Code/bin/code"` → sh 脚本,可从 WSL 直接调用
2. **修复**:
   ```bash
   mkdir -p ~/.local/bin
   printf '#!/bin/sh\nexec "/mnt/d/Apps/Microsoft VS Code/bin/code" "$@"\n' > ~/.local/bin/code
   chmod +x ~/.local/bin/code
   ```
3. **验证**:`code --version` → `1.142.0 / 6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1 / x64` ✅

## 结果

- `code .` / `code <dir>` / `code <file>` 在独立终端可用,自动走 WSL Remote(`~/.vscode-server`);
- 未触碰 `/etc/wsl.conf`、未改 PATH(`~/.local/bin` 原本就在)、无需重开终端;
- Windows 其余工具(node/npm 等)依旧不进 WSL PATH,09-26 的隔离决策不受影响。

## 回滚

```bash
rm ~/.local/bin/code
```

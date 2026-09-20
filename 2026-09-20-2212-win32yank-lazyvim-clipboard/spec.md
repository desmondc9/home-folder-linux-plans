# win32yank 打通 WSL LazyVim → Windows 11 剪贴板 记录

- 日期:2026-09-20 22:12
- 环境:WSL2 Ubuntu 26.04(yaoshi15pro 笔记本)+ LazyVim / NVIM v0.12.5
- 状态:用户实施并实测通过(事后记录)

## 1. 问题

LazyVim 中按 `y` 复制的内容进不了 Windows 11 剪贴板:WSL 内没有 X11/Wayland 剪贴板服务,neovim 的 clipboard provider(默认 `unnamedplus`)探测不到可用工具,复制静默落空,Windows 侧粘贴不出来。

## 2. 方案

安装 [equalsraf/win32yank](https://github.com/equalsraf/win32yank)(Windows 剪贴板桥的小工具)到 `~/.local/bin`。NVIM 在 WSL 环境下会自动把 PATH 里的 `win32yank.exe` 选为剪贴板 provider(自动探测顺序对 WSL 优先 win32yank),因此**无需改任何 LazyVim / neovim 配置**,放下二进制即生效。

否决的备选:
- `clip.exe`:只能单向写入(复制),且带 CRLF 换行问题,粘贴方向(`p`)不可用
- WSLg / X11 剪贴板服务:重,非必需

## 3. 实施命令(2026-09-20 21:55 执行,原文记录)

```bash
curl -sLo /tmp/win32yank.zip https://github.com/equalsraf/win32yank/releases/download/v0.1.1/win32yank-x64.zip
unzip -p /tmp/win32yank.zip win32yank.exe > ~/.local/bin/win32yank.exe
chmod +x ~/.local/bin/win32yank.exe
```

要点:
- 只从 zip 中取出内层 `win32yank.exe` 直接落到 `~/.local/bin`(该目录已在 PATH,同目录还有 lazygit)
- 版本固定 v0.1.1(上游最新;该项目 2021 年后未再发版)
- PE32+ Windows 二进制,经 WSL interop 调用 Windows 剪贴板 API

## 4. 验证

- LazyVim 中 `y` 复制 → Windows 11 任意应用可直接粘贴(用户实测通过)
- 落盘确认:`~/.local/bin/win32yank.exe`,`-rwxr-xr-x`,PE32+ x86-64,1.1M(2026-09-20 21:55)
- 备份影响:位于 home 内,随 restic 白名单备份带走(还原即得,无需重装;见 `plans/2026-09-20-2145-restic-azure-backup-wsl-manual/`)

## 5. 参考

- https://github.com/equalsraf/win32yank
- neovim 剪贴板 provider 探测:`:h clipboard`、`:checkhealth provider`

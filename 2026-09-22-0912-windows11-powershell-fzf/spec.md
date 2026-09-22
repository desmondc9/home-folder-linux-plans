# Windows 11 PowerShell 下使用 fzf 模糊搜索

日期:2026-09-22 · 状态:指南归档(待 Win11 实机重放验证) · 类型:工具配置 how-to

- 环境:Windows 11 物理机 DESKTOP-J7NBNU4,PowerShell(Windows Terminal)

## 背景

PowerShell 里最方便的模糊搜索方式是装 `fzf` + `PSFzf`:fzf 提供通用的模糊过滤引擎,PSFzf 模块把它接进 PSReadLine,获得 `Ctrl+T` / `Ctrl+R` / `Alt+C` 三个快捷键,覆盖文件插入、历史命令、目录跳转三个高频场景。

## 1. 安装 fzf

```powershell
winget install --id junegunn.fzf -e
```

重开 PowerShell 后确认:

```powershell
Get-Command fzf
```

## 2. 安装 PowerShell 集成模块

```powershell
Install-Module -Name PSFzf -Scope CurrentUser
```

## 3. 启用快捷键,写进 `$PROFILE`

```powershell
Import-Module PSFzf
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -PSReadlineChordSetLocation 'Alt+c'
```

如果 `$PROFILE` 不存在:

```powershell
if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force }
notepad $PROFILE
```

## 4. 常用快捷键

- `Ctrl+T`:模糊搜索当前目录下的文件/目录,插入到命令行
- `Ctrl+R`:模糊搜索历史命令
- `Alt+C`:模糊选择目录并 `cd` 进去

## 5. 命令行里直接用(管道)

```powershell
Get-ChildItem -Recurse | fzf
Get-ChildItem -Recurse -File | fzf | ForEach-Object { code $_ }
git log --oneline | fzf
Set-Location (Get-ChildItem -Directory | fzf)
```

## 6. 故障排查

`Ctrl+T` / `Ctrl+R` 没反应:通常是 `PSReadLine` 没加载或版本太旧。先执行 `Import-Module PSReadLine` 再执行 `Import-Module PSFzf`。

## 参考

- fzf:https://github.com/junegunn/fzf
- PSFzf:https://github.com/kelleyma49/PSFzf

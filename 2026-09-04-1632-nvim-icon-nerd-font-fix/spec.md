# nvim 图标不显示 — 根因调查与修复(Nerd Font)

- 日期:2026-09-04 16:32
- 类型:本机环境调查 + 修复(无 repo 代码变更,无 PR)
- 状态:已修复,用户已确认(2026-09-04,重启 Konsole 后 tabline / dashboard 图标均正常)

## 背景

用户发现 nvim 中部分图标不显示(如 tabline 的 close icon)。要求确认当前 nvim 配置是什么,并排查图标缺失原因。

## 现状分析

### nvim 配置

- NVIM v0.11.6,配置位于 `~/.config/nvim/`
- **stock LazyVim**:`lazyvim.json` 的 `extras` 为空,`lua/plugins/` 无自定义插件(`example.lua` 未启用),`options.lua`/`keymaps.lua`/`autocmds.lua` 均为空模板
- tabline 由 `bufferline.nvim` 渲染,图标由 `mini.icons` 提供——全部依赖 **Nerd Font 私有区字形**(PUA,如 U+F00D ``)

### 证据链(根因确认)

| 命令 | 结果 | 结论 |
|---|---|---|
| `grep Font ~/.local/share/konsole/*.profile` | 所有 profile 字体为 Noto Mono / Ubuntu Mono | 终端字体不含 NF 字形 |
| `fc-list ':charset=f00d' family` | 仅 FontAwesome / Liberation Serif / Unifont 含 U+F00D | 系统默认等宽字体均无 NF 码点 |
| `fc-list \| grep -i nerd`(修复前) | 无任何命中 | 系统未装 Nerd Font |
| `fc-list \| grep -iE "jetbrains\|hack"` | JetBrains Mono / Hack 均为普通版 | 已装字体也非 NF 版 |

**根因**:Konsole 默认 profile 字体(Noto Mono)不包含 Nerd Font 图标码点,LazyVim/bufferline/mini.icons 输出的 PUA 字形无法渲染,显示为空缺/豆腐块。与 nvim 配置本身无关。

## 修复内容

1. **安装 JetBrainsMono Nerd Font**(经本地代理 `127.0.0.1:10809` 从 GitHub 下载):
   - 下载 `https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz` → 解压至 `~/.local/share/fonts/JetBrainsMonoNerdFont/`(与已有的非 NF 版 `~/.local/share/fonts/JetBrainsMono/` 共存,family 名不同不冲突)
   - `fc-cache -f ~/.local/share/fonts`
   - 验证:`fc-list ':charset=f00d'` 现包含 `JetBrainsMono Nerd Font (Mono)` 全系字重
2. **修改 Konsole 默认 profile**:`~/.local/share/konsole/Kubuntu Light Desmond.profile`(`konsolerc` 中 `DefaultProfile`)的 `Font` 由 `Noto Mono,14` 改为 `JetBrainsMono Nerd Font Mono,14`

## 验证

- [x] 字体安装并进入 fontconfig 缓存(charset 查询命中)
- [x] 用户开**新的** Konsole 窗口/session 运行 nvim,确认 tabline close 图标等正常显示(已打开的 session 不会自动换字体)

## 追加调查(2026-09-04 16:40):dashboard 图标仍不显示

用户反馈 snacks dashboard 的 Restore Session / Lazy Extras 等图标仍未显示。追加证据:

- 从 `~/.local/share/nvim/lazy/LazyVim/lua/lazyvim/plugins/ui.lua` 提取按钮图标码点:Restore Session = U+E348,Lazy Extras = U+EA8C
- lazy.nvim UI 图标(`lazy/core/config.lua`):nf-md 高区码点 U+F04B2(󰒲 sleep)、U+F08B1(󰢱 lua)等;emoji 图标由 Konsole 回退到已装的 Noto Color Emoji(`/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf`)
- `fc-list ':charset=…'` 逐一核对:U+E348 / U+EA8C / U+F04B2 / U+F08B1 在 JetBrainsMono Nerd Font Mono 中**全部覆盖**(7 字重)
- 唯一 Konsole 进程(PID 5722)启动于 **09:05**,早于字体安装时间 **16:23**(注意:tar 解压保留上游 mtime 2026-08-21,目录 ctime 16:23:32 才是真实安装时间)

**结论**:字体与码点覆盖均无问题;旧 Konsole 进程的 Qt 字体库/内存中 profile 未刷新,开新标签/新窗口无效(Konsole 单进程多窗口)。**修复动作:完全退出 Konsole(所有窗口)后重开**——本 opencode 会话亦运行在该进程内,退出前需先结束会话。

## 遗留 / 跟进

- 其余 Konsole profile(`Dark`、`Light`、`Profile Desmond`、`Kubuntu Dark Desmond`)字体仍为 Noto Mono / Ubuntu Mono,若日常切换使用需同样更换(设置 → Edit Current Profile → Appearance,或批量改 profile 文件)
- nvim 配置本身无需改动;如后续想去掉图标依赖可换 `mini.icons` 的 ASCII 风格,但非必要

## 参考

- Nerd Fonts releases: https://github.com/ryanoasis/nerd-fonts
- LazyVim 对 Nerd Font 的要求: https://www.lazyvim.org/

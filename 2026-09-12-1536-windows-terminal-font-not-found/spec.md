# Windows Terminal 找不到 JetBrains Mono NL / Sarasa Mono SC — 根因调查与修复

- 日期:2026-09-12 15:36
- 类型:本机环境调查 + 修复(无 repo 代码变更,无 PR)
- 状态:已修复并经用户确认(WT 以新字体正常运行,警告消失);18:05 追加 face 切 NF 家族修复图标豆腐块(见「追加」)

## 环境

> 按新约定(2026-09-12 起),`~/plans` 的 spec 必须写明环境信息,便于今后跨机器复用。

- 操作系统:**Windows 11 物理机**(DESKTOP-J7NBNU4),AI 经 WSL2(mirrored networking)interop 拉起 `powershell.exe` 代跑;安装脚本需 UAC 提权(用户点确认)
- 终端:Windows Terminal `Microsoft.WindowsTerminal 1.24.11911.0`(Store 打包应用)
- 涉事字体:JetBrains Mono / JetBrains Mono NL / NL NerdFontMono + Sarasa Mono SC 全家族,共 58 个字体文件
- WT 配置:`C:\Users\Desmond\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`(WSL 侧 `/mnt/c/Users/Desmond/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`),`profiles.defaults.font.face` 写的是 CSS 式逗号回退列表 `"JetBrains Mono NL, Sarasa Mono SC"`

## 背景

WT 启动弹警告:`Unable to find the following fonts: JetBrains Mono NL, Sarasa Mono SC. Please either install them or choose different fonts.`,字体回退 Consolas。要求 debug 修复。

## 证据链(根因确认)

| 步骤 | 证据 | 结论 |
|---|---|---|
| 读 settings.json | `face: "JetBrains Mono NL, Sarasa Mono SC"`(逗号列表) | 先怀疑写法不支持 |
| 查字体文件 + 注册表 | 两字体**均已安装**,HKCU `...\Fonts` 登记完整、家族名与配置逐字匹配 | 方向转为「已安装但对 WT 不可见」 |
| 查 WT 文档/源码版本 | WT 1.24,报错串来自 `RendererErrorFontNotFound` | 版本较新,排除老版本问题 |
| GDI+/WPF 枚举探针 | 两个家族**枚举不到**;且探针进程经核实跑在 session 1 交互式用户上下文,排除「WSL 拉起= session 0 看不见用户字体」的假象 | 字体对系统字体枚举确实不可见 |
| 读 WT 源码 `AtlasEngine.api.cpp` `_resolveFontMetrics` | `til::iterate_font_families(faceName, ...)` 逐个 `FindFamilyName`,找不到的拼进 `missingFontNames` 并以 `DWRITE_E_NOFONT` 回调 | **WT 1.24 支持逗号回退列表,配置写法本身没问题**;是 DirectWrite 系统字体集合里 `FindFamilyName` 返回不存在 |
| 查上游 issue | [microsoft/terminal#15344](https://github.com/microsoft/terminal/issues/15344) "Per-user fonts don't load" | 实锤:WT(打包应用)的 DWrite 系统字体集合**不包含仅当前用户安装的字体** |

字体来源追溯:当天两个 session 都以「复制到 `%LOCALAPPDATA%\Microsoft\Windows\Fonts` + 只写 HKCU + `AddFontResourceW` 热加载」的免管理员方式装字体——12:20 装 Sarasa Mono SC 10 字重,13:12–13:28 的 [lazyvim-wsl-replay](../2026-09-12-1319-lazyvim-wsl-replay/) 在 Windows 侧装 JetBrainsMonoNL NerdFontMono 16 权重——均为 per-user 安装,埋下此雷。

**根因**:字体此前按「仅当前用户」方式安装(HKCU + `%LOCALAPPDATA%`),而 WT 的 DirectWrite 系统字体集合不含 per-user 字体(#15344),`FindFamilyName` 两家全部 miss,遂弹警告回退 Consolas。与 `face` 的逗号列表写法无关。

## 修复内容

提权 PowerShell 脚本 `C:\Users\Desmond\font-fix-tmp\install-fonts.ps1`(日志同目录 `install-log.txt` / `result.log`),把 58 个字体文件从用户级转入**系统级安装**:

1. 扫描 HKCU 中值指向 `%LOCALAPPDATA%\...\Fonts` 的 JetBrains/Sarasa 条目(58 条)
2. 复制到 `C:\Windows\Fonts` + 写 HKLM 注册表(值为相对文件名,系统级惯例)——这正是 WT 能识别的安装方式
3. `Unblock-File` 清除 Mark-of-the-Web(JetBrains 字体下载自带)
4. `AddFontResourceW` 逐个加载 + `SendMessageTimeout(HWND_BROADCAST, WM_FONTCHANGE)` 广播字体变更
5. 重启 `FontCache` 服务
6. 清理用户级旧条目:删 HKCU 登记 + 删 `%LOCALAPPDATA%` 下的旧文件副本

## 验证

- [x] 新进程枚举:`JetBrains Mono NL`、`Sarasa Mono SC`(含全部字重子家族)均可见
- [x] HKLM 58 条登记、`C:\Windows\Fonts` 文件在位
- [x] HKCU 残留 = 0,用户级旧文件已删
- [x] 用户完全关闭所有 WT 窗口后重开,警告消失(2026-09-12 用户以该字体正常使用 nvim 确认)

## 经验教训

- **给 WT(及一切 UWP/打包应用)装字体必须走系统级安装**(`C:\Windows\Fonts` + HKLM,或右键字体文件→「为所有用户安装」);「复制文件 + 只写 HKCU」的 per-user 方式对 WT 的 DirectWrite 不可见(#15344),GDI 老应用却能看到,极具迷惑性
- WT 1.24 的 `face` 支持 CSS 式逗号回退列表,配置写法无辜时别急着改配置
- 从 WSL interop 拉起的 Windows 进程不一定跑在 session 0——用进程 session id + 交互性核实后再下「探针被污染」的结论,避免冤枉/漏判证据

## 追加(2026-09-12 18:05):nvim 图标不显示 → face 换 NF 家族

WT 警告已消失、字体正常渲染(用户回报),但 LazyVim 图标豆腐块:WT 的 `face` 指向**原版** `JetBrains Mono NL`(不含 Nerd Font PUA 字形,与母本 [2026-09-04-1632-nvim-icon-nerd-font-fix](../2026-09-04-1632-nvim-icon-nerd-font-fix/) 同款),而 NF 字形的家族名是另一个——`GlyphTypeface` 实读 name table:`JetBrainsMonoNL NFM / JetBrainsMonoNL Nerd Font Mono`(Win32 家族名/DWrite 家族名)。修复:`face` 改为 `"JetBrainsMonoNL Nerd Font Mono, Sarasa Mono SC"`(Sarasa 保留 CJK 回退),新开 WT 窗口生效。

**经验**:「装了字体」≠「用上字体」——WT 的 face 匹配的是 DWrite 家族名,与注册表 GDI 名(`JetBrainsMonoNLNerdFontMono-*`)还不一样,以 name table 为准。

## 遗留 / 跟进

- `C:\Users\Desmond\font-fix-tmp\` 日志目录,用户确认警告消失后可删
- Kubuntu 侧 Konsole 的同类字体问题另见 [2026-09-04-1632-nvim-icon-nerd-font-fix](../2026-09-04-1632-nvim-icon-nerd-font-fix/)(Linux fontconfig 体系,与本次 Windows 注册表体系互为对照)

## 参考

- microsoft/terminal#15344 "Per-user fonts don't load": https://github.com/microsoft/terminal/issues/15344
- WT `face` 设置文档: https://learn.microsoft.com/windows/terminal/customize-settings/appearance

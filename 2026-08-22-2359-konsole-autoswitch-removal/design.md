# 移除 Konsole 随系统主题自动切换 profile 的 rig(自动部分)

日期: 2026-08-22
状态: 已完成并验证——自动 rig 全部拆除,手动 toggle 保留,默认 profile 修正为 Dark

## 背景

本次开机后系统仍是 dark,但 Konsole 却切成了 light 主题。用户决定**不再需要** Konsole 根据系统 Theme 自动切换 profile。原 rig 于 2026-05-20 由 AI 搭建(记忆档案 konsole-theme-autoswitch),本次只拆"自动"部分,保留手动 toggle(Meta+Shift+T)与 Light/Dark profiles 供手动使用。

## 现状分析

原 rig 组成(见记忆档案):
- `~/.config/systemd/user/konsole-follow-theme.{path,service}` — path 单元盯 `~/.config/kdeglobals`,变化即跑 `konsole-set-theme.sh follow`(自动部分,本次拆除)
- `~/.local/bin/konsole-set-theme.sh {light|dark|follow|toggle}` — 切换脚本(保留,供手动 toggle)
- `~/.local/share/konsole/{Light,Dark}.profile` + `Breeze{Light,Dark}.colorscheme`(保留)
- `Meta+Shift+T` 快捷键:`dev.user.konsole-toggle-theme.desktop` + `kglobalshortcutsrc`(保留)

拆除前实测状态:`konsole-follow-theme.path` enabled+active;`konsolerc` `DefaultProfile=Light.profile`(开机误判遗留)。

**开机误判机理**(简述,归档用):登录早期 Plasma 重写 kdeglobals → path 单元在系统配色尚未最终落定时触发 → 脚本读到的 ColorScheme 与最终状态不一致 → 误设 light。

## 方案

1. `systemctl --user disable --now konsole-follow-theme.path`
2. 删除两个 unit 文件 + `systemctl --user daemon-reload`
3. `konsolerc` `DefaultProfile`:Light.profile → Dark.profile(当前系统 dark)
4. 手动 toggle、profiles、colorschemes、快捷键全部保留

不做的事:不删 profiles/colorschemes/脚本/快捷键(手动切换仍有价值);不动已打开的 Konsole 窗口(Konsole 无法外部切换可见标签,需重开窗口才用新默认 profile——Konsole 25.x 已知限制,见记忆档案)。

## 验收标准

- [x] `systemctl --user list-unit-files` 无 konsole-follow-theme 相关单元
- [x] `systemctl --user cat konsole-follow-theme.path` → No files found
- [x] `konsolerc` `DefaultProfile=Dark.profile`
- [x] 手动 toggle 三件套(脚本/desktop/快捷键)健在
- [ ] 下次开机 Konsole 直接是 Dark(待下次开机确认)

## 风险与缓解

- 基本无风险;若日后想要回自动跟随,可从 git 历史/记忆档案重建两个 unit 文件。
- 已打开的 Konsole 窗口颜色不变是 Konsole 已知限制,重开窗口即 Dark。

# Dark Reader "Use system color scheme" 警告调查与验证

**日期**: 2026-08-26
**性质**: 系统配置任务(排查 + 验证,无代码改动)
**结论**: 警告是 Dark Reader 对 Linux 平台的**硬编码文案**,非实测故障;本机 Chrome 的系统配色跟随链路经实测**完全正常**(含实时切换)。

## 1. 背景

Chrome 中 Dark Reader 扩展启用 "Use system color scheme"(跟随系统配色)时,设置项旁提示:

> This option might not work due to a bug in your browser

环境:Kubuntu 26.04 / KDE Plasma 6(Wayland)/ Chrome stable 152.0.7977.64(运行中实例为 151,待重启升级)/ Dark Reader 4.9.129(extension ID `eimadpbcbfnmbkopoojfekhnkhdbieeh`)。

## 2. 调查过程(systematic-debugging 四阶段)

### Phase 1 根因调查

从本机已安装的扩展 bundle 反查警告文案:

- 消息 key:`system_dark_mode_chromium_warning`(`_locales/en/messages.json`)
- 触发条件(`ui/popup/index.js:1297`,`ui/options/index.js` 同):

```js
const isMatchMediaChangeEventListenerBuggy =
    (isNavigatorDefined &&
        navigator.userAgentData &&
        ["Linux", "Android"].includes(navigator.userAgentData.platform)) ||
    platform.startsWith("linux");
```

**平台是 Linux 即无条件显示警告**,不做任何运行时探测。针对的是老 Chromium Linux 上 matchMedia change listener 不触发的 bug。

Dark Reader 的实际机制(针对该 bug 的自保 workaround):向所有页面注入 `inject/color-scheme-watcher.js`,页面可见时检测 `prefers-color-scheme` 并经 `COLOR_SCHEME_CHANGE` 消息回报 background——不依赖扩展页自身的 matchMedia 事件。

### Phase 2 模式分析(应然链路)

```
KDE 配色切换
  → xdg-desktop-portal-kde(6.6.4,按 QApplication::palette() 亮度判定,不读 kdeglobals 键)
  → DBus org.freedesktop.portal.Settings.SettingChanged (org.freedesktop.appearance color-scheme: 1=dark 2=light)
  → Chrome 更新 prefers-color-scheme(含 renderer 媒体查询失效广播)
  → Dark Reader 页面 watcher / 扩展自身 感知并切换
```

本机配置核对:portal 三件套(kde/gtk/generic)在跑;Chrome 启动 flags 仅 VAAPI 相关;`browser.theme.color_scheme(2)=0`(system,0=system/1=light/2=dark,旧键已废弃);KDE 为 BreezeLight 时 portal 报 2,一致。

### Phase 3 实测验证(真实 Chrome,临时 profile + CDP)

| 测试 | 结果 |
|---|---|
| 桌面 dark 时启动真 Chrome(headed) | `PCS_DARK=True` ✓ 正确 |
| 运行中切 BreezeLight,2.5s 后查询 | `False` ✓ 实时更新 |
| 运行中注册 matchMedia change listener 再切 dark→light | `events=dark,light` ✓ 事件正常触发 |
| headless Chrome 反复切换/换 profile 重启 | 每次启动都正确跟随环境,profile 无粘滞 |

DBus 抓包同时证实:plasma-apply-colorscheme 触发后 portal 即刻发出 `SettingChanged`(1↔2 准确),portal 侧无延迟无丢失。

### 走过的弯路(记录以免重蹈)

- Playwright MCP 启动的 Chrome(即使就是真 Chrome 二进制)在该 flag 环境下 `prefers-color-scheme` **恒为 light**,与桌面/portal/GTK 配置全部无关——是 Playwright 启动环境的伪影,**不能**作为该问题的证据平台。验证浏览器行为须用用户式直接启动(本次用 `--remote-debugging-port` + CDP)。
- `kdeglobals` 缺 `ColorScheme` 键、`kdedefefaults` 兜底 BreezeLight,对 portal 6.6.4 无影响(其读 QPalette 不读配置键)。
- `gtk-application-prefer-dark-theme` / `gtk-theme-name`(KDE 在 BreezeDark 下写 `true`/`Breeze`,非 `Breeze-Dark`)单独翻转均不改变 headed Chrome 的上报值——Chromium 实际以 portal 为准。
- portal 枚举:**1=prefer dark,2=prefer light**(易记反)。

## 3. 结论与处置

1. **警告文案**:Dark Reader 上游对 Linux 硬编码,无法通过配置消除,亦无需消除;功能不受其影响。
2. **功能**:本机 Chrome 对系统配色的读取与实时跟随均正常,Dark Reader "Use system color scheme" 可放心使用。
3. **无需任何系统侧修改**;未做代码变更。

## 4. 验收标准(回顾)

- 能指出警告的确切触发代码及条件 ✓
- 用非 Playwright 的真实浏览器实例证明 prefers-color-scheme 初值正确 ✓
- 证明运行中实时切换有效(值 + change 事件)✓
- 系统状态还原(BreezeLight、GTK 配置、无残留进程/临时文件)✓

## 5. 参考

- Dark Reader 源码逻辑:本机 bundle `.../Extensions/eimadpbcbfnmbkopoojfekhnkhdbieeh/4.9.129_0/`
- xdg-desktop-portal-kde 6.6.4 `src/settings.cpp`(invent.kde.org,`FdoAppearanceSettings::readFdoColorScheme`)
- XDG settings portal 规范(color-scheme 枚举)

# Chrome 原生 dark mode 上游调研(2026-08-26)

> 调研日期:2026-08-26。目标环境:desktop Chrome on **Linux**,stable 152 / beta 153(版本背景见 §0)。
> 本报告为**上游调研**(官方文档 / Chromium 源码 / GitHub / 官网第一手来源),本地实测由主会话补充(见文末空节)。
> 所有网络来源均为当日抓取;Chromium 源码引用基于 fetch 当日的 `main` 分支。

---

## 0. 版本背景

- **Chrome 152 已确认于 2026-08-25 进入 stable channel**:[Chrome Releases 官方博客](https://chromereleases.googleblog.com/)当日文章原文:"The Chrome team is delighted to announce the promotion of Chrome 152 to the stable channel for ..." (desktop)。
- **Chrome 153 beta**:未在本次调研中单独核实(未确认),按 Chromium 发布节奏与主会话设定采用。
- 本文引用的 Chromium `main` 分支源码即对应 153+ 的开发线。

---

## 1. Chrome 自身 UI 主题自动切换(浏览器界面)

### 结论

**是——desktop Chrome 原生支持跟随系统 light/dark 切换浏览器 UI,并提供浏览器内覆写选项(Light / Dark / Device)。**

### 事实与来源

1. **当前官方文档的设置路径**([Chrome Help "Browse in Dark mode or Dark theme"(Desktop 版)](https://support.google.com/chrome/answer/9275525?hl=en&co=GENIE.Platform%3DDesktop),原文逐字):

   > "At the bottom right of a New Tab page, select **Customize Chrome**. Under **'Appearance,'** select either:
   > **Light** — Chrome will be in a light theme.
   > **Dark** — Chrome will be in a dark theme.
   > **Device** — Chrome will follow your device's theme."

   即 New Tab 页右下角 "Customize Chrome" 侧面板 → Appearance → **Light / Dark / Device** 三选一。Device 即"跟随系统"。

2. **`chrome://settings/appearance` 是否有同样的选择器**:多个二手来源(如 [YouTube 教程](https://www.youtube.com/watch?v=nL87hX9vU2A)演示 Settings → Appearance → "Mode" 下拉)显示 Settings 页有同名 "Mode" 选择器,与 Customize Chrome 面板是同一设置;**官方 Help 文章只写了 Customize Chrome 路径,未写 settings 路径**(未确认项,留本地实测核对 Linux 上两个入口的形态)。

3. **历史沿革**:
   - Chrome 73(2019-03)macOS 首次支持系统 dark mode([ZDNet 报道](https://www.zdnet.com/article/google-chrome-73-released-with-dark-mode-support-on-macos/));
   - Chrome 74(2019-04)Windows 10 跟进([Gizmodo 报道](https://gizmodo.com/google-is-finally-rolling-out-chromes-dark-mode-for-win-1834268990));
   - **Linux 的引入版本:未找到官方一手来源确认**(未确认)。Linux 上 Chrome UI 长期跟随 GTK 主题偏好,此说法同样缺一手文档,留本地实测。
   - 浏览器内 Light/Dark/Device **手动选择器的引入版本:未确认**。可考的里程碑:"Customize Chrome" 侧面板 2023-05 上线([9to5Google, 2023-05-23](https://9to5google.com/2023/05/23/customize-chrome-side-panel/));Chrome 117 前后(2023-09~11)的 "Material You" 改版将 Light/Dark 主题选项纳入该面板([9to5Google, 2023-09-07](https://9to5google.com/2023/09/07/chrome-material-you-redesign/)、[2023-11-10](https://9to5google.com/2023/11/10/google-chrome-material-you-redesign/))。合理推断为 Chrome 114–117 区间,但**无官方 changelog 佐证,标注未确认**。

4. **Linux 可用性**:官方 Help 的 Desktop 文章在"如何在系统中开启 dark mode"一节只列出 Mac / Windows / Chromebook 的指引链接,**未单列 Linux**(该文抓取于 2026-08-26)。设置本身在 Chromium 中是跨平台 WebUI,但 Linux 形态(尤其与 GTK 主题的交互)留本地实测。

---

## 2. Chrome 原生网页内容变暗(不装扩展)

### 2a. `prefers-color-scheme` 媒体查询(早已 stable)

**结论:自 Chrome 76(2019-07)起 stable 支持,至今(Chrome 152)仍是标准机制。支持原生暗色的网站(GitHub、Reddit 等)在系统处于 dark 时自动变暗,无需任何扩展。**

- 官方教程:[web.dev "prefers-color-scheme: Hello darkness, my old friend"](https://web.dev/articles/prefers-color-scheme) 原文:"At the time of writing, `prefers-color-scheme` is supported on both desktop and mobile (where available) by Chrome and Edge as of version 76"(Firefox 67、Safari 12.1 同文列出)。
- 特性跟踪页:[chromestatus "Media Queries: prefers-color-scheme feature"](https://chromestatus.com/feature/5109758977638400)。
- caniuse 原始数据([features-json/prefers-color-scheme.json](https://raw.githubusercontent.com/Fyrd/caniuse/main/features-json/prefers-color-scheme.json)):Chrome 首个 `"y"` 版本为 **76**。
- 注意:这只对**网站自己写了 dark 样式**的站点生效;对不支持的站点毫无作用——这正是需要"强制变暗"方案的空档。

### 2b. "Auto Dark Mode for Web Contents"(`chrome://flags/#enable-force-dark`)

**结论:截至 2026-08-26,该功能在 desktop 上仍是 chrome://flags 实验 flag,从未毕业为正式设置;在 Android 上则以 "Darken websites" 开关(Settings → Theme)形式存在过正式化路径。**

1. **Desktop 现状(一手源码证据)**:Chromium `main` 分支 [`chrome/browser/about_flags.cc`](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/about_flags.cc)(2026-08-26 抓取)中该 flag 仍然存在,逐字:

   ```cpp
   {"enable-force-dark", flag_descriptions::kAutoWebContentsDarkModeName,
    flag_descriptions::kAutoWebContentsDarkModeDescription, kOsAll,
    FEATURE_VALUE_TYPE(blink::features::kForceWebContentsDarkMode)},
   ```

   - flag 名 `enable-force-dark`,UI 名称 "Auto Dark Mode for Web Contents";
   - `kOsAll` —— **全平台可用,包括 Linux desktop**;
   - 对应 Blink feature:`blink::features::kForceWebContentsDarkMode`。

2. **生命周期(一再"续命")**:该 flag 曾计划在 Chrome 123 失效,后 Google 延期至 Chrome 136([How-To Geek, 2024-04-12 更新](https://www.howtogeek.com/google-chrome-123-forced-dark-mode/) 原文:"Google has extended the feature flag to last until Chrome 136, so it's safe for now");而如上,2026-08 的 `main` 分支(>136 十几个版本)它依然在。同一文引用 Chromium commit 原文:"This flag is one of the more popular flags and will be difficult to remove. Usage is slowly falling so lets re-evaluate in a year." —— 即 Google 自己也承认它受欢迎但始终未转正。

3. **Android 的正式化路径**(与 desktop 不同):
   - [developer.chrome.com 官方博客 "Auto Dark Theme"](https://developer.chrome.com/blog/auto-dark-theme)(Chrome 96 起 Android origin trial):官方定位是"对浅色站点自动生成暗色主题";文档给出 Android 手机上的启用法——先开 `chrome://flags/#darken-websites-checkbox-in-theme-setting` 实验,再在 **Settings → Theme** 勾选 "Apply Dark themes to sites, when possible"。
   - 该 "Darken websites" 开关后进入 stable([9to5Google, 2019-08 起的追踪](https://9to5google.com/2019/08/28/android-chrome-webview-web-dark-mode/)、[XDA](https://www.xda-developers.com/google-chrome-dark-mode-darken-web-pages/));**哪一版本正式化:未确认**(现行 [Chrome Help Android 版](https://support.google.com/chrome/answer/9275525?hl=en&co=GENIE.Platform%3DAndroid)只文档化了 Settings → Theme 的 System Default / Dark / Light 三项 UI 主题,未提 "Darken websites")。
   - **Desktop 从未有对应的正式设置** —— 官方 Help(desktop 版)全文没有任何"强制网页变暗"选项,唯一入口就是 flag(与源码一致)。

4. **质量(已知渲染问题)**:
   - 算法本质是浏览器侧自动反色/再映射,对图片、品牌色、图表常出现失真。一手/接近一手的记录:
     - [govuk-frontend issue #2582 "Various issues under Chrome's Auto Dark Mode"](https://github.com/alphagov/govuk-frontend/issues/2582) —— 英国政府前端团队汇总的各类渲染问题,并给站长的缓解建议(设置 `<meta name="color-scheme" content="light">` 等)。
     - [Reddit r/chrome:Chrome 141.0.7390.55 引入回归](https://www.reddit.com/r/chrome/comments/1nwebdk/latest_version_1410739055_introduces_bug_to_auto/) —— "CIELAB-based inversion and selective image inversion are reportedly malfunctioning"(社区证据,表明该 flag 的反色算法仍会随版本引入回归、无人兜底)。
   - 无 per-site 配置、无白名单(除网站自查 `<meta name="color-scheme">` / prefers-color-scheme 自适配外),这是与 Dark Reader 类扩展的最大体验差距。

### 2c. 其他原生机制

- **CSS `color-scheme` 属性**:Chrome **81** 起支持(MDN BCD 原始数据 [color-scheme.json](https://raw.githubusercontent.com/mdn/browser-compat-data/main/css/properties/color-scheme.json):`"version_added": "81"`;[MDN 文档](https://developer.mozilla.org/en-US/docs/Web/CSS/color-scheme))。它让页面声明配色方案,使原生控件(表单、滚动条)跟随暗色——是网站侧配合 `prefers-color-scheme` 的机制,不是用户侧强制开关。
- **DevTools 模拟**(开发调试用):Rendering 面板提供 "Emulate auto dark mode" 与 "Emulate CSS media feature prefers-color-scheme"([官方博客 Auto Dark Theme](https://developer.chrome.com/blog/auto-dark-theme) 记录了前者)。仅调试用,非用户功能。
- **用户侧 override 设置:desktop 不存在**。Chrome 没有任何正式设置能让用户"强制所有网站按 `prefers-color-scheme: dark` 渲染"或覆盖该查询的返回值;唯一用户侧机制就是上面的 flag。CWS 主题(Themes)只改浏览器 UI,不影响网页内容。

---

## 3. Dark Reader 在 2026-08 的状态

仓库:[darkreader/darkreader](https://github.com/darkreader/darkreader)(GitHub API,2026-08-26 查询)

| 维度 | 事实 |
|---|---|
| 维护活跃度 | **活跃**:最近 push 2026-08-24(两天前);未归档 |
| 最近 release | v4.9.129(2026-07-14)、v4.9.128(2026-06-19)、v4.9.127(2026-06-05)……约每月一版([releases](https://github.com/darkreader/darkreader/releases)) |
| 规模 | 22,293 stars;open issues 1,448(其 issue 模板大量是自动分流的 broken-website 报告) |
| 许可 | MIT(开源) |
| CWS 安装量 | **7,000,000 users**([Chrome Web Store 页面](https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh));[darkreader.org](https://darkreader.org/) 自称全浏览器 "Trusted by 10,000,000 users. Developed since 2014." |
| 隐私 | 官方隐私页([darkreader.org/privacy](https://darkreader.org/privacy/))原文:"Dark Reader extension has never collected and will never collect any personal data, browsing history, etc.";官网:"It doesn't send user's data anywhere."(开源可审计;社区有[讨论 #1386](https://github.com/darkreader/darkreader/issues/1386) 提醒其可能收集技术性数据用于兼容性,非浏览历史) |

### Manifest V3 状态(重点核实)

- 背景:Google 已完成 MV2 退场。[官方时间线](https://developer.chrome.com/docs/extensions/develop/migrate/mv2-deprecation-timeline) 原文:
  - "Mar 31st 2025: Manifest V2 is disabled with the option to re-enable extensions"(全渠道默认禁用、可手动重开);
  - "**Jul 24th 2025: Manifest V2 is disabled everywhere** — With Chrome 138 all users on all channels of Chrome have now Manifest V2 extensions disabled";
  - 企业策略 `ExtensionManifestV2Availability` 随 Chrome 139 移除,"Manifest V2 extensions will cease to function for any user upgrading to Chrome 139 and subsequent versions"。
  → **在当前 stable 152 上,MV2 扩展已完全不可用;所有在用扩展必然是 MV3。**
- Dark Reader 仓库形态:默认 [`src/manifest.json`](https://github.com/darkreader/darkreader/blob/main/src/manifest.json) 仍是 **MV2**(`"manifest_version": 2`, persistent background page,version 4.9.129),另有独立的 [`src/manifest-chrome-mv3.json`](https://github.com/darkreader/darkreader/blob/main/src/manifest-chrome-mv3.json)(`"manifest_version": 3`,`"minimum_chrome_version": "106.0.0.0"`,`background.service_worker`)。
- **CWS 现行版本为 MV3 构建(强证据推断)**:CWS Dark Reader 页面内嵌的 manifest 片段含 `minimum_chrome_version: "106.0.0.0"` + `action` 键,与 `manifest-chrome-mv3.json` 完全吻合(MV2 manifest 无此二者);且 MV2 在 139+ 已无法运行,CWS 稳定版不可能仍是 MV2。维护者 Gusted 2022-07-05 在 [discussion #9193](https://github.com/darkreader/darkreader/discussions/9193) 的原话可作历史注脚:"Nope, we're still polishing out the version to be compatible with Manifest v3. We only publish it as part of our automated releases."
- **功能退化(MV3 后)与已知痛点(一手 issue)**:
  - [#13084 "Flash of dark styling"](https://github.com/darkreader/darkreader/issues/13084)(open)与 [#11190 "Brief white page when opening links in new window"](https://github.com/darkreader/darkreader/issues/11190)(open,2023 起)—— FOUC/白闪类问题长期存在;
  - [#13236 "Local storage memory leak (TabManager)"](https://github.com/darkreader/darkreader/issues/13236)(open);
  - [#13661 "Chrome lags when Dark Reader extension is enabled"](https://github.com/darkreader/darkreader/issues/13661)(closed)—— 性能抱怨的代表性 issue;
  - 安全:[CVE-2025-68467](https://www.sentinelone.com/vulnerability-database/cve-2025-68467/)(跨域 stylesheet 内容泄露,2025,已修复)。
  - "MV3 迁移导致 per-site 数据丢失":本次**未找到一手 issue 佐证**(未确认;如需可后续在 issue tracker 定向检索)。

---

## 4. Dark Reader 替代品对比(desktop Chrome)

| 方案 | 开源 | 隐私/遥测 | 质量 | 性能 | 维护状态 | 适合人群 |
|---|---|---|---|---|---|---|
| **Chrome 原生 `#enable-force-dark`**([flag](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/about_flags.cc) / [Chrome Help](https://support.google.com/chrome/answer/9275525?hl=en&co=GENIE.Platform%3DDesktop)) | 是(浏览器内置) | 无扩展、无第三方代码 | **不可控**:算法反色,图片/品牌色易失真([govuk #2582](https://github.com/alphagov/govuk-frontend/issues/2582));无 per-site 配置;曾随版本回归([Reddit 141 案例](https://www.reddit.com/r/chrome/comments/1nwebdk/latest_version_1410739055_introduces_bug_to_auto/)) | 最好(原生 C++) | 随 Chromium;flag 随时可能被移除(123→136 一再延期,现状见 §2b) | 愿意接受渲染瑕疵、追求零扩展/零开销的人;备机/临时用 |
| **Dark Reader**([GitHub](https://github.com/darkreader/darkreader) / [CWS](https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh)) | **MIT** | 官方声明零收集([privacy](https://darkreader.org/privacy/));开源可审计 | per-site 配置、亮度/对比度/滤镜可调;白闪/内存泄漏等长期 issue(§3) | 中(有卡顿类 issue 记录) | **活跃**(2026-08-24 仍有 push) | 主流选择:要可控、可调、可审计的全站变暗 |
| **Midnight Lizard**([GitHub](https://github.com/Midnight-Lizard/Midnight-Lizard) / [官网](https://midnight-lizard.org/) / [CWS](https://chromewebstore.google.com/detail/midnight-lizard/pbnndmlekkboofhnbonilimejonapojg)) | **MIT** | 开源可审计;无官方隐私声明页(未确认) | 卖点是**任意配色方案**(非纯黑:蓝光滤镜、高对比、灰度等),每 scheme 全站通用 | 社区长期反馈偏重(定性口碑,**未找到一手基准**,标注) | **放缓**:731 stars;repo 最后 push 2025-12-24(约 8 个月前);GitHub release 停在 10.4(2019-06),CWS 列表约 30,000 users、"Updated January …"(年份抓取不全,未确认) | 想要"非黑即彩"的自定义配色、不追新的人 |
| **Night Eye**([官网](https://nighteye.app/) / [定价页](https://nighteye.app/plans-and-pricing/)) | **否(闭源)** | 自称 "No ads, no data mining … does not monitor, process nor store your browsing activity"(官网原文);闭源不可审计 | 宣传"智能转换而非简单反色"、小图标/图片单独处理(官网自述);有客服体系 | 未测(未确认) | 商业持续运营,自称 1M+ users | 愿意付费换省心+跨浏览器同步体验的人:**免费 Lite 仅 5 个网站/1 浏览器**;Pro $9/年、Pro Max $14/年、Ultimate $40 买断(2026-08 定价页) |
| **Dark Mode(简单扩展)**([CWS](https://chromewebstore.google.com/detail/dark-mode/dmghijelimhndkbmpgbldicpogfkceaj)) | 否 | 闭源小工具;CWS 描述:"helps you quickly turn the screen (browser) to dark at night time"(以浏览器/页面简单变暗为主,选项页配置) | 简单反色/滤镜类,无精细调校;评分一般 | 轻 | 更新频率与开发者背景未深查(未确认);约 1,000,000 users | 极简、一次性需求;隐私敏感者不建议(闭源+宽权限) |
| **Stylus + 用户样式**([GitHub openstyles/stylus](https://github.com/openstyles/stylus) / [userstyles.world](https://userstyles.world/)) | **GPL-3.0** | README 原文:"**No analytics/tracking** - this is our foundational principle as Stylus was created solely because the original Stylish extension was sold to a Web analytics company."(Stylus 正是为去遥测而生的 Stylish 分支) | 质量取决于所装样式:大站(GitHub 等)社区样式经多年打磨,效果接近原生;小站/无样式站点则无解 | **最好**(纯 CSS 注入,无算法运算) | **非常活跃**:repo push 2026-08-26(当天),v2.4.11 发布于 2026-08-19;6,842 stars | 主要活动在少数大站、在意性能与隐私的人;配合站点**原生** `prefers-color-scheme`(GitHub 等已内置暗色)几乎零成本 |

**选型速记**:
- 只要浏览器 UI 跟随系统:原生 Device 选项即可(§1),无需任何扩展。
- 常去的站多数已支持原生暗色:什么都不用装(§2a);个别没有的站用 Stylus 补社区样式。
- 要"全网默认变暗 + 可调可控 + 开源无遥测":Dark Reader 仍是默认答案。
- 不想装扩展、能忍受瑕疵:开 `chrome://flags/#enable-force-dark`(注意它是实验 flag,可能随版本回归/被移除)。
- 要花式配色:Midnight Lizard(接受维护放缓)或 Stylus 自写样式。

---

## 5. 事实速查表

| # | 事实 | 关键来源 |
|---|---|---|
| 1 | Chrome 152 于 2026-08-25 进入 stable(desktop) | [Chrome Releases 博客](https://chromereleases.googleblog.com/) |
| 2 | Desktop Chrome UI 有 Light/Dark/Device 三选一(Customize Chrome → Appearance);Device=跟随系统 | [Chrome Help (Desktop)](https://support.google.com/chrome/answer/9275525?hl=en&co=GENIE.Platform%3DDesktop) |
| 3 | 该手动选择器引入版本:未确认(约 2023 年中,Customize Chrome 侧面板/Material You 改版时期) | [9to5Google 2023-05](https://9to5google.com/2023/05/23/customize-chrome-side-panel/)、[2023-11](https://9to5google.com/2023/11/10/google-chrome-material-you-redesign/) |
| 4 | Linux 平台 UI dark mode 引入版本与行为:未确认(官方 Help 未单列 Linux),留本地实测 | 同上 Help 页 |
| 5 | `prefers-color-scheme`:Chrome 76 起 stable;支持原生暗色的网站自动跟随系统,零扩展 | [web.dev](https://web.dev/articles/prefers-color-scheme)、[chromestatus](https://chromestatus.com/feature/5109758977638400)、[caniuse data](https://raw.githubusercontent.com/Fyrd/caniuse/main/features-json/prefers-color-scheme.json) |
| 6 | CSS `color-scheme`:Chrome 81 起 | [MDN BCD](https://raw.githubusercontent.com/mdn/browser-compat-data/main/css/properties/color-scheme.json) |
| 7 | `#enable-force-dark`(Auto Dark Mode for Web Contents)截至 2026-08-26 仍是 desktop flag,`kOsAll`(含 Linux),feature=`blink::features::kForceWebContentsDarkMode`;无正式设置 | [about_flags.cc(main)](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/about_flags.cc) |
| 8 | 该 flag 曾定于 Chrome 123 失效→延期至 136→至今仍在;Chromium commit 自述"one of the more popular flags … difficult to remove" | [How-To Geek](https://www.howtogeek.com/google-chrome-123-forced-dark-mode/) |
| 9 | Android 的对应功能是 Settings → Theme 的 "Darken websites"(源自 Chrome 96 Auto Dark Theme origin trial;正式化版本未确认);现行 Android Help 只写 UI 主题三选项 | [developer.chrome.com 博客](https://developer.chrome.com/blog/auto-dark-theme)、[Chrome Help (Android)](https://support.google.com/chrome/answer/9275525?hl=en&co=GENIE.Platform%3DAndroid) |
| 10 | force-dark 质量:图片反色/颜色失真类问题长期存在,且会随版本回归(141 案例);无 per-site 配置 | [govuk-frontend #2582](https://github.com/alphagov/govuk-frontend/issues/2582)、[Reddit](https://www.reddit.com/r/chrome/comments/1nwebdk/latest_version_1410739055_introduces_bug_to_auto/) |
| 11 | Desktop 无任何正式的"强制网页变暗"用户设置;DevTools 仅提供调试用模拟 | [Chrome Help (Desktop)](https://support.google.com/chrome/answer/9275525?hl=en&co=GENIE.Platform%3DDesktop)、[developer.chrome.com](https://developer.chrome.com/blog/auto-dark-theme) |
| 12 | MV2 扩展自 Chrome 139+ 完全失效(2025-03-31 默认禁用,2025-07-24/Chrome 138 全渠道禁用,企业策略 139 移除) | [MV2 support timeline](https://developer.chrome.com/docs/extensions/develop/migrate/mv2-deprecation-timeline) |
| 13 | Dark Reader:活跃维护(push 2026-08-24),v4.9.129(2026-07-14),MIT,22.3k stars;CWS 7M users | [GitHub](https://github.com/darkreader/darkreader)、[CWS](https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh) |
| 14 | Dark Reader 仓库默认 manifest 仍 MV2,另有 chrome 专用 MV3 manifest;CWS 现行版本为 MV3 构建(强证据推断:页面内嵌 min_chrome 106 + action 与 MV3 manifest 吻合 + MV2 已不可运行) | [manifest.json](https://github.com/darkreader/darkreader/blob/main/src/manifest.json)、[manifest-chrome-mv3.json](https://github.com/darkreader/darkreader/blob/main/src/manifest-chrome-mv3.json)、CWS 页面 |
| 15 | Dark Reader 隐私:官方声明"从未也永远不会收集个人数据/浏览历史";痛点一手 issue:白闪 #13084/#11190、内存泄漏 #13236、卡顿 #13661;CVE-2025-68467(已修) | [privacy](https://darkreader.org/privacy/)、issues 见 §3 |
| 16 | Stylus:GPL-3.0,极活跃(v2.4.11,2026-08-19),README 明言"No analytics/tracking"是其立身原则 | [GitHub](https://github.com/openstyles/stylus) |
| 17 | Midnight Lizard:MIT,约 30k CWS users;维护放缓(repo 最后 push 2025-12-24,GitHub release 停在 2019) | [GitHub](https://github.com/Midnight-Lizard/Midnight-Lizard)、[CWS](https://chromewebstore.google.com/detail/midnight-lizard/pbnndmlekkboofhnbonilimejonapojg) |
| 18 | Night Eye:闭源商业,免费 Lite 限 5 网站,Pro $9/年起,Ultimate $40 买断(2026-08) | [定价页](https://nighteye.app/plans-and-pricing/) |

---

## 本地实测(主会话补充,2026-08-26,Kubuntu 26.04 / KDE Plasma 6 Wayland / Chrome 152.0.7977.64)

实测方法:临时 profile + `--remote-debugging-port` + CDP(WebSocket)驱动真 Chrome;截图经视觉分析比对。**结论与上游调研一致,无翻案项。**

### 1. 浏览器 UI 跟随系统(对应 §1)

- 本目录 [design.md](./design.md) 的 Phase 1 调查(§1)已用 CDP 证实:真 Chrome 对 `prefers-color-scheme` 的读取**初值正确且实时跟随**(切配色 2.5s 内生效,change 事件双向触发)。浏览器 UI 主题同源跟随(portal 链路已验证健康)。
- `chrome://settings/appearance`(Linux 152)**没有** Light/Dark/Device 行;取而代之有一个 Linux 特有的 **Theme 下拉**(Use Classic / Use GTK / Qt)——浏览器界面用哪套平台主题渲染的选择器。Light/Dark/Device 官方入口在 NTP "Customize Chrome" 侧面板,该面板是**浏览器级侧栏**,页面级截图拍不到,未做像素级验证(官方 Help 已记载,见 §1)。

### 2. `#enable-force-dark` 存在性与质量(对应 §2b)

- **flag 在 stable 152 上存在**(chrome://flags 深度 DOM 文本抽取原文命中):`Auto Dark Mode for Web Contents / Automatically render all web contents using a dark theme. / #enable-force-dark`,与上游 `about_flags.cc` 的 `kOsAll` 一致。同页还有相关 flag:`#root-scrollbar-follows-browser-theme`、neutral palette for dark mode("Enabled Color Scheme Only" / "Enabled Animation and Color Scheme" 两档)、`#enable-cross-device-theme-tracker`。
- **质量实测**(自建测试页:白底 + 彩色标题 + 灰卡片 + 内联 code + 蓝按钮 + 引用块 + 真实照片;`--enable-features=WebContentsForceDark` 启动后截图):
  - 照片**未反色**——被压暗但保留原色相(浅蓝壁纸变成深蓝灰,非橙红反相);
  - 蓝按钮保持蓝色、卡片/引用/code 块均正确翻转为深底浅字;
  - 唯一小瑕疵:标题(蓝色)对深底对比度略低。
  - **注意**:测试页结构干净,是 force-dark 的理想场景;复杂真实站点的失真风险仍以 §2b 的 govuk/Reddit 一手记录为准。
- 截图存档:`screenshots/shot-baseline.png`、`shot-forcedark.png`、`shot-darkreader.png`。

### 3. Dark Reader 对照(对应 §3/§4)

- 同一测试页、snap Chromium 151 + `--load-extension` 加载 DR 4.9.129(dynamic 默认档):生效(`data-darkreader-mode` 标记 + body 背景 `rgb(24,26,27)`),照片保持自然,整体观感即用户日常所见。
- **工作流坑(重要)**:品牌 Chrome(stable/beta)已**忽略 `--load-extension`**(加载后扩展列表为空)——要跑扩展注入类实验必须用 Chromium/Chrome for Testing;snap Chromium 还读不到 `~/.config` 下(点开头路径)的扩展目录,需复制到非隐藏路径;扩展默认不碰 `file://` 页面,测试页要走 localhost HTTP。

### 4. 综合判定(本地视角)

1. Chrome **浏览器 UI** 跟随系统:原生可用,零配置(本机链路已验证健康)。
2. **支持原生暗色的网站**:系统 dark 时自动变暗,零扩展(`prefers-color-scheme` 实时跟随已验证)。
3. **不支持暗色的网站**:Chrome 原生唯一手段是 `#enable-force-dark`——本机实测质量尚可但无 per-site 控制、且随版本可能回归;**Dark Reader 仍是"全网可控变暗"的最优解**(开源、活跃、per-site 配置)。
4. 替代品里值得考虑的组合:Stylus + 大站社区样式(性能最好)或原生 flag(零开销),按访问习惯取舍。

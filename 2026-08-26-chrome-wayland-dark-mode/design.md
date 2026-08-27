# Linux Wayland + Chrome light/dark 自动切换:调研与落地

**日期**: 2026-08-26
**性质**: 系统配置任务(排查验证 + 上游调研 + 浏览器扩展配置优化)
**环境**: Kubuntu 26.04 / KDE Plasma 6(Wayland)/ Chrome stable 152.0.7977.64(取证时运行实例为 151,待重启升级)/ Dark Reader 4.9.129(extension ID `eimadpbcbfnmbkopoojfekhnkhdbieeh`)
**结论**: Dark Reader "Use system color scheme" 警告是 Linux 硬编码文案且本机跟随链路健康;Chrome 原生暗色能力有限(UI 可跟随、内容变暗只有实验 flag),Dark Reader 仍是最优解;据此用 Chrome 历史 + CDP 双遍实测筛出 **11 个原生支持系统配色自动切换**的站点加入 DR `disabledFor`,把自带暗色的站交还给网站自己。

## 0. 总览:同一件事的三个阶段

本档案由三个连续任务合并而成(2026-08-26 同日完成),共同主题是 **Linux Wayland 桌面与 Chrome 中 light/dark 的自动切换**:

| 阶段 | 问题 | 结论 | 详见 |
|---|---|---|---|
| Phase 1 警告调查 | DR "Use system color scheme" 旁的警告是否意味着功能坏了 | 警告是 DR 对 Linux 平台的**硬编码文案**,非实测故障;本机 KDE → xdg-desktop-portal → Chrome 跟随链路实测完全健康(含实时切换) | §1 |
| Phase 2 上游调研 | 不装扩展,Chrome 原生能把"跟随系统变暗"做到什么程度 | 浏览器 UI 跟随系统原生可用;网页内容原生唯一手段是 `#enable-force-dark` 实验 flag(无 per-site 控制、随版本可能回归);DR 仍是最优解,但**自带暗色的站点应交还网站自己** | §2 + [upstream-research.md](./upstream-research.md) |
| Phase 3 排除名单落地 | 具体哪些站点该进 DR 排除名单 | 从 Chrome 历史取高频站,CDP 双遍实测筛出 11 站加入 `disabledFor` | §3 |

最终落地状态:Chrome UI 跟随系统(原生);11 个自带暗色站点交还网站自己渲染(`prefers-color-scheme`);其余不支持暗色的站点由 Dark Reader 跟随系统配色兜底。

## 1. Phase 1:Dark Reader "Use system color scheme" 警告调查

### 1.1 背景

Chrome 中 Dark Reader 扩展启用 "Use system color scheme"(跟随系统配色)时,设置项旁提示:

> This option might not work due to a bug in your browser

### 1.2 调查过程(systematic-debugging 四阶段)

#### 根因调查

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

#### 模式分析(应然链路)

```
KDE 配色切换
  → xdg-desktop-portal-kde(6.6.4,按 QApplication::palette() 亮度判定,不读 kdeglobals 键)
  → DBus org.freedesktop.portal.Settings.SettingChanged (org.freedesktop.appearance color-scheme: 1=dark 2=light)
  → Chrome 更新 prefers-color-scheme(含 renderer 媒体查询失效广播)
  → Dark Reader 页面 watcher / 扩展自身 感知并切换
```

本机配置核对:portal 三件套(kde/gtk/generic)在跑;Chrome 启动 flags 仅 VAAPI 相关;`browser.theme.color_scheme(2)=0`(system,0=system/1=light/2=dark,旧键已废弃);KDE 为 BreezeLight 时 portal 报 2,一致。

#### 实测验证(真实 Chrome,临时 profile + CDP)

| 测试 | 结果 |
|---|---|
| 桌面 dark 时启动真 Chrome(headed) | `PCS_DARK=True` ✓ 正确 |
| 运行中切 BreezeLight,2.5s 后查询 | `False` ✓ 实时更新 |
| 运行中注册 matchMedia change listener 再切 dark→light | `events=dark,light` ✓ 事件正常触发 |
| headless Chrome 反复切换/换 profile 重启 | 每次启动都正确跟随环境,profile 无粘滞 |

DBus 抓包同时证实:plasma-apply-colorscheme 触发后 portal 即刻发出 `SettingChanged`(1↔2 准确),portal 侧无延迟无丢失。

#### 走过的弯路(记录以免重蹈)

- Playwright MCP 启动的 Chrome(即使就是真 Chrome 二进制)在该 flag 环境下 `prefers-color-scheme` **恒为 light**,与桌面/portal/GTK 配置全部无关——是 Playwright 启动环境的伪影,**不能**作为该问题的证据平台。验证浏览器行为须用用户式直接启动(本次用 `--remote-debugging-port` + CDP)。
- `kdeglobals` 缺 `ColorScheme` 键、`kdedefaults` 兜底 BreezeLight,对 portal 6.6.4 无影响(其读 QPalette 不读配置键)。
- `gtk-application-prefer-dark-theme` / `gtk-theme-name`(KDE 在 BreezeDark 下写 `true`/`Breeze`,非 `Breeze-Dark`)单独翻转均不改变 headed Chrome 的上报值——Chromium 实际以 portal 为准。
- portal 枚举:**1=prefer dark,2=prefer light**(易记反)。

### 1.3 结论与处置

1. **警告文案**:Dark Reader 上游对 Linux 硬编码,无法通过配置消除,亦无需消除;功能不受其影响。
2. **功能**:本机 Chrome 对系统配色的读取与实时跟随均正常,Dark Reader "Use system color scheme" 可放心使用。
3. **无需任何系统侧修改**;未做代码变更。

## 2. Phase 2:Chrome 原生暗色能力调研(摘要)

完整报告见 [upstream-research.md](./upstream-research.md)(官方文档 / Chromium 源码 / 一手 issue + 本地实测,含 18 条事实速查表)。要点:

- **浏览器 UI 跟随系统**:原生支持(NTP "Customize Chrome" → Appearance → Light / Dark / Device 三选一);Linux 152 的 `chrome://settings/appearance` 没有该选择器,代之以 Linux 特有的 Theme 下拉(Use Classic / GTK / Qt)。
- **网页内容变暗**:`prefers-color-scheme` 自 Chrome 76 stable——支持原生暗色的网站(GitHub 等)自动跟随系统,零扩展;**强制变暗的唯一用户侧手段**是 `#enable-force-dark` 实验 flag——截至 2026-08-26 仍在 stable(`kOsAll`,含 Linux),本地实测质量尚可,但无 per-site 控制、曾随版本回归、从未正式化。
- **替代品对比**:Dark Reader(MIT、活跃维护、per-site 配置)仍是"全网可控变暗"最优解;Stylus + 社区样式是大站轻量替代;Midnight Lizard 维护放缓;Night Eye 闭源收费。
- **与 Phase 3 的衔接结论**:保留 DR 当兜底,但把自带暗色的站点交还给网站自己。

## 3. Phase 3:Dark Reader per-site 排除名单:自带暗色的站点交还给网站自己

### 3.1 背景与目标

Phase 2 调研(§2)的结论是:**保留 Dark Reader 当兜底,但把自带暗色的站点交还给网站自己**。理由:

- 网站原生暗色是设计者调过的,几乎总比扩展的算法合成好看;
- Dark Reader 对每个页面注入 content script + 动态改写样式,排除后这些站零开销;
- 已知 DR 痛点(白闪 FOUC、内存泄漏)在被排除的站上自然消失。

本任务把这个结论落地:**用数据而非猜测**决定哪些站进排除列表。

### 3.2 方法

#### 站点来源:Chrome History

读 `~/.config/google-chrome/Default/History`(SQLite,`urls` 表)的副本,按注册域聚合 `visit_count`,过滤:

- 近 180 天内有访问(`last_visit_time`,Chrome epoch = 1601-01-01,需减 11644473600 秒);
- 排除 `chrome://` / `file://` / `localhost` / 自建基础设施域;
- 排除纯认证域(microsoftonline / live.com 等)与登录墙后台。

取前 ~26 个候选站进入实测。

#### 判定标准:两遍实测

关键认识:**站点适配 `prefers-color-scheme` 有两种实现方式**,单一测法会漏判。

| Pass | 方法 | 捕获的站点类型 |
|---|---|---|
| **Pass 1 实时翻转** | 页面加载后用 CDP `Emulation.setEmulatedMedia` 把 `prefers-color-scheme` 由 light 切到 dark,采样 `body`/`html` 背景色亮度 | 监听 `matchMedia` change 事件、**运行时**响应的站 |
| **Pass 2 暗色下全新加载** | 先设 `prefers-color-scheme: dark`,再 `Page.navigate` 全新加载,采样亮度 | **仅在加载时读一次**配色的站(Pass 1 会假阴性) |

亮度用相对亮度公式 `0.2126R + 0.7152G + 0.0722B`(归一化到 0–1):

- Pass 1 判定 FLIP:`light_lum > 0.55 且 dark_lum < 0.45 且 差值 > 0.2`
- Pass 2 判定 DARK-ON-BOOT:`dark_boot_lum < 0.45`

测试用**临时 profile 的真实 Chrome**(`--remote-debugging-port` + CDP),经本地代理访问,**不触碰用户正在使用的 Chrome**,也不改动桌面主题。

#### 现有配置读取:Dark Reader 的 LevelDB

DR 4.9 开启 `syncSettings` 后,设置存在 **`Sync Extension Settings/<ext-id>/`** 而非 `Local Extension Settings/`。该目录是 LevelDB,当前状态全在 `.log`(WriteBatch 格式,未压实)里。

解析要点(踩坑记录见 §4):

- WriteBatch 记录:`seq(8B) + count(4B)`,后接 `type(1B) + varint(klen) + key + varint(vlen) + value`;
- **键名有位移**:实际存储的 key 缺首字符、并带 1 字节写入计数后缀(如 `automation` 存为 `utomation3`),需按 `field[1:]` 前缀匹配还原;
- **大值会跨 batch 分裂**:key 所在 batch 到末尾即截断,value 出现在下一个 batch 的空 key 记录里,需要合并;
- 值前可能有 1–3 字节长度前缀,用 `json.JSONDecoder().raw_decode()` 容错解析。

### 3.3 实测结果

#### 通过(11 站,已加入 disabledFor)

| 站点 | 判定 | 数据 |
|---|---|---|
| github.com | Pass 1 实时翻转 | 1.00 → 0.07 |
| claude.ai | Pass 1 实时翻转 | 0.99 → 0.08 |
| kimi.com | Pass 1 实时翻转 | 0.98 → 0.09 |
| cursor.com | Pass 1 实时翻转 | 0.97 → 0.07 |
| cloudflare.com | Pass 1 实时翻转 | 1.00 → 0.08 |
| google.com | Pass 2 加载即暗 | 0.14 |
| youtube.com | Pass 2 加载即暗 | 0.06 |
| x.com | Pass 2 加载即暗 | 0.00 |
| okx.com | Pass 2 加载即暗 | 0.00 |
| v.qq.com | Pass 2 加载即暗 | 0.08 |
| `__ADULT_SITE_REDACTED__` | Pass 2 加载即暗 | 0.00 |

#### 未通过(继续由 Dark Reader 接管)

bilibili.com(0.95)、apple.com.cn(1.00)、notion.com(1.00)、supabase.com(1.00)、bandwagonhost.com(0.86)、douyu.com、dedao.cn、nvidia.com、godaddy.com、minimaxi.com、z.ai、amazon.com、skills.sh

其中 bilibili 另测了视频内页,同样无原生暗色。

### 3.4 变更内容

只改 `disabledFor` 一个字段,其余原样保留:

```
disabledFor: []  →  11 个站点(见 §3.3)
```

保持不变的关键设置:

- `automation`: `{enabled: true, mode: "system", behavior: "OnOff"}`(跟随系统配色)
- `enabled`: `true`、`enabledByDefault`: `true`
- `syncSettings`: `true`(⚠️ 导入后会同步到同账号的其他 Chrome)
- `customThemes`: 4 条内置 cssFilter 规则(officeapps.live.com / sharepoint.com / docs.google.com / onedrive.live.com)
- `theme`(dynamicTheme 引擎)、`time`(18:00–9:00)、`detectDarkTheme` 等全部保留

交付方式:生成完整的 `Dark-Reader-Settings.json`,经 DR 官方 **Manage settings → Import Settings** 导入。**未直接改写运行中 Chrome 的扩展数据库**(会被内存状态覆盖或损坏)。

## 4. 踩坑记录(Phase 3)

1. **只测实时翻转会漏一半站点**。YouTube/Google/X 等只在加载时读一次配色,Pass 1 全部假阴性——必须补 Pass 2 的暗色全新加载。
2. **bilibili 会搞崩 CDP 连接**(`no close frame received or sent`),连带污染后续站点的采样数据(标题与域名错位)。修复:每站独立 WebSocket 连接 + 崩溃后自动重启浏览器 + 结果与标题交叉核对。
3. **DR 设置在 sync 而非 local 存储**。先翻 `Local Extension Settings` 只找到 TabManager/Newsmaker 等运行时状态,`disabledFor` 在 `Sync Extension Settings` 里。
4. **LevelDB `.log` 的键名位移与值分裂**(见 §3.2),是本任务耗时最多的一环。
5. **导入 JSON 必须字段完整**。DR 的 `validateSettings()` 对缺失字段会回落到 `DEFAULT_SETTINGS`,只提交 `{disabledFor: [...]}` 会把其他设置重置掉。

## 5. 验收

### 5.1 Phase 1(警告调查)

- [x] 能指出警告的确切触发代码及条件 ✓
- [x] 用非 Playwright 的真实浏览器实例证明 prefers-color-scheme 初值正确 ✓
- [x] 证明运行中实时切换有效(值 + change 事件)✓
- [x] 系统状态还原(BreezeLight、GTK 配置、无残留进程/临时文件)✓

### 5.2 Phase 3(per-site 排除)

- [x] 站点来源基于真实访问频次,非凭空猜测
- [x] 每个入选站有可复现的亮度数据支撑(两种判定方式)
- [x] 崩溃导致的污染数据已识别并剔除
- [x] 生成的 JSON 通过 DR 校验规则模拟检查(23 字段齐全、类型正确)
- [x] 用户已导入成功
- [x] 用户浏览历史副本、扩展数据库副本已删除;测试浏览器已关闭;用户 Chrome 全程未动
- [x] 归档前脱敏(公开仓库)

## 6. 隐私说明

本档案基于用户浏览历史,而 `~/plans` 是**公开仓库**。归档时已做脱敏:

- 成人站点域名替换为 `__ADULT_SITE_REDACTED__`(出现在 `Dark-Reader-Settings.json`、`probe-results-pass2.json`、探测脚本中);
- **实际导入 Chrome 的文件保留真实值**,位于 `~/Downloads/darkreader/Dark-Reader-Settings.json`(未入库);
- 历史统计中的账号 ID、内部工作域(ADO / sharepoint / 公司系统 / 自建基础设施)未写入本档案。

## 7. 参考

- Phase 2 完整调研报告:[upstream-research.md](./upstream-research.md)(官方文档 / Chromium 源码 / 替代品对比 + 本地实测与截图)
- Dark Reader 源码逻辑:本机 bundle `~/.config/google-chrome/Default/Extensions/eimadpbcbfnmbkopoojfekhnkhdbieeh/4.9.129_0/`(警告触发 `ui/popup/index.js:1297`;watcher `inject/color-scheme-watcher.js`;设置校验 `ui/options/index.js` 的 `validateSettings` / `DEFAULT_SETTINGS`)
- xdg-desktop-portal-kde 6.6.4 `src/settings.cpp`(invent.kde.org,`FdoAppearanceSettings::readFdoColorScheme`)
- XDG settings portal 规范(color-scheme 枚举)

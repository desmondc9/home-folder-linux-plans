# Dark Reader per-site 排除名单:自带暗色的站点交还给网站自己

**日期**: 2026-08-26
**性质**: 系统配置任务(浏览器扩展配置优化)
**结论**: 从 Chrome 历史提取高频站点,实测出 **11 个原生支持系统配色自动切换**的站点,加入 Dark Reader `disabledFor`(不启用)列表。网站原生暗色优于扩展合成,同时省去这些站的注入开销。

## 1. 背景与目标

前序档案 [2026-08-26-chrome-native-dark-mode-research](../2026-08-26-chrome-native-dark-mode-research/upstream-research.md) 的结论是:**保留 Dark Reader 当兜底,但把自带暗色的站点交还给网站自己**。理由:

- 网站原生暗色是设计者调过的,几乎总比扩展的算法合成好看;
- Dark Reader 对每个页面注入 content script + 动态改写样式,排除后这些站零开销;
- 已知 DR 痛点(白闪 FOUC、内存泄漏)在被排除的站上自然消失。

本任务把这个结论落地:**用数据而非猜测**决定哪些站进排除列表。

## 2. 方法

### 2.1 站点来源:Chrome History

读 `~/.config/google-chrome/Default/History`(SQLite,`urls` 表)的副本,按注册域聚合 `visit_count`,过滤:

- 近 180 天内有访问(`last_visit_time`,Chrome epoch = 1601-01-01,需减 11644473600 秒);
- 排除 `chrome://` / `file://` / `localhost` / 自建基础设施域;
- 排除纯认证域(microsoftonline / live.com 等)与登录墙后台。

取前 ~26 个候选站进入实测。

### 2.2 判定标准:两遍实测

关键认识:**站点适配 `prefers-color-scheme` 有两种实现方式**,单一测法会漏判。

| Pass | 方法 | 捕获的站点类型 |
|---|---|---|
| **Pass 1 实时翻转** | 页面加载后用 CDP `Emulation.setEmulatedMedia` 把 `prefers-color-scheme` 由 light 切到 dark,采样 `body`/`html` 背景色亮度 | 监听 `matchMedia` change 事件、**运行时**响应的站 |
| **Pass 2 暗色下全新加载** | 先设 `prefers-color-scheme: dark`,再 `Page.navigate` 全新加载,采样亮度 | **仅在加载时读一次**配色的站(Pass 1 会假阴性) |

亮度用相对亮度公式 `0.2126R + 0.7152G + 0.0722B`(归一化到 0–1):

- Pass 1 判定 FLIP:`light_lum > 0.55 且 dark_lum < 0.45 且 差值 > 0.2`
- Pass 2 判定 DARK-ON-BOOT:`dark_boot_lum < 0.45`

测试用**临时 profile 的真实 Chrome**(`--remote-debugging-port` + CDP),经本地代理访问,**不触碰用户正在使用的 Chrome**,也不改动桌面主题。

### 2.3 现有配置读取:Dark Reader 的 LevelDB

DR 4.9 开启 `syncSettings` 后,设置存在 **`Sync Extension Settings/<ext-id>/`** 而非 `Local Extension Settings/`。该目录是 LevelDB,当前状态全在 `.log`(WriteBatch 格式,未压实)里。

解析要点(踩坑记录见 §5):

- WriteBatch 记录:`seq(8B) + count(4B)`,后接 `type(1B) + varint(klen) + key + varint(vlen) + value`;
- **键名有位移**:实际存储的 key 缺首字符、并带 1 字节写入计数后缀(如 `automation` 存为 `utomation3`),需按 `field[1:]` 前缀匹配还原;
- **大值会跨 batch 分裂**:key 所在 batch 到末尾即截断,value 出现在下一个 batch 的空 key 记录里,需要合并;
- 值前可能有 1–3 字节长度前缀,用 `json.JSONDecoder().raw_decode()` 容错解析。

## 3. 实测结果

### 3.1 通过(11 站,已加入 disabledFor)

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

### 3.2 未通过(继续由 Dark Reader 接管)

bilibili.com(0.95)、apple.com.cn(1.00)、notion.com(1.00)、supabase.com(1.00)、bandwagonhost.com(0.86)、douyu.com、dedao.cn、nvidia.com、godaddy.com、minimaxi.com、z.ai、amazon.com、skills.sh

其中 bilibili 另测了视频内页,同样无原生暗色。

## 4. 变更内容

只改 `disabledFor` 一个字段,其余原样保留:

```
disabledFor: []  →  11 个站点(见 §3.1)
```

保持不变的关键设置:

- `automation`: `{enabled: true, mode: "system", behavior: "OnOff"}`(跟随系统配色)
- `enabled`: `true`、`enabledByDefault`: `true`
- `syncSettings`: `true`(⚠️ 导入后会同步到同账号的其他 Chrome)
- `customThemes`: 4 条内置 cssFilter 规则(officeapps.live.com / sharepoint.com / docs.google.com / onedrive.live.com)
- `theme`(dynamicTheme 引擎)、`time`(18:00–9:00)、`detectDarkTheme` 等全部保留

交付方式:生成完整的 `Dark-Reader-Settings.json`,经 DR 官方 **Manage settings → Import Settings** 导入。**未直接改写运行中 Chrome 的扩展数据库**(会被内存状态覆盖或损坏)。

## 5. 踩坑记录

1. **只测实时翻转会漏一半站点**。YouTube/Google/X 等只在加载时读一次配色,Pass 1 全部假阴性——必须补 Pass 2 的暗色全新加载。
2. **bilibili 会搞崩 CDP 连接**(`no close frame received or sent`),连带污染后续站点的采样数据(标题与域名错位)。修复:每站独立 WebSocket 连接 + 崩溃后自动重启浏览器 + 结果与标题交叉核对。
3. **DR 设置在 sync 而非 local 存储**。先翻 `Local Extension Settings` 只找到 TabManager/Newsmaker 等运行时状态,`disabledFor` 在 `Sync Extension Settings` 里。
4. **LevelDB `.log` 的键名位移与值分裂**(见 §2.3),是本任务耗时最多的一环。
5. **导入 JSON 必须字段完整**。DR 的 `validateSettings()` 对缺失字段会回落到 `DEFAULT_SETTINGS`,只提交 `{disabledFor: [...]}` 会把其他设置重置掉。

## 6. 验收

- [x] 站点来源基于真实访问频次,非凭空猜测
- [x] 每个入选站有可复现的亮度数据支撑(两种判定方式)
- [x] 崩溃导致的污染数据已识别并剔除
- [x] 生成的 JSON 通过 DR 校验规则模拟检查(23 字段齐全、类型正确)
- [x] 用户已导入成功
- [x] 用户浏览历史副本、扩展数据库副本已删除;测试浏览器已关闭;用户 Chrome 全程未动
- [x] 归档前脱敏(公开仓库)

## 7. 隐私说明

本档案基于用户浏览历史,而 `~/plans` 是**公开仓库**。归档时已做脱敏:

- 成人站点域名替换为 `__ADULT_SITE_REDACTED__`(出现在 `Dark-Reader-Settings.json`、`probe-results-pass2.json`、探测脚本中);
- **实际导入 Chrome 的文件保留真实值**,位于 `~/Downloads/darkreader/Dark-Reader-Settings.json`(未入库);
- 历史统计中的账号 ID、内部工作域(ADO / sharepoint / 公司系统 / 自建基础设施)未写入本档案。

## 8. 参考

- 前序档案:[2026-08-26-chrome-native-dark-mode-research](../2026-08-26-chrome-native-dark-mode-research/upstream-research.md)、[2026-08-26-darkreader-system-color-scheme](../2026-08-26-darkreader-system-color-scheme/design.md)
- Dark Reader 4.9.129 bundle:`~/.config/google-chrome/Default/Extensions/eimadpbcbfnmbkopoojfekhnkhdbieeh/`
- 校验逻辑:该 bundle 的 `ui/options/index.js`(`validateSettings` / `DEFAULT_SETTINGS`)

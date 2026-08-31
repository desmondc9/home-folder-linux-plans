# 实施记录 — Linux Wayland + Chrome light/dark 自动切换

**结果类型**: 三阶段——排查验证(Phase 1,无变更)+ 上游调研报告(Phase 2)+ 浏览器扩展配置变更(Phase 3,经官方导入,附实测脚本)。

## 步骤

### Phase 1:DR 系统配色警告调查

- [x] 1. 全量搜索历史 session(`.remember/` 全部 md、`~/.claude/projects/` 转录、`~/plans/`)——无既往处理记录(仅 Konsole 主题切换,不同主题)
- [x] 2. 定位警告文案 key 与触发条件(bundle 反查,`ui/popup/index.js:1297`)
- [x] 3. 阅读 `inject/color-scheme-watcher.js` 确认 DR 自身 workaround 机制
- [x] 4. 环境取证:Chrome 版本/flags、portal 三件套、kdeglobals/kdedefaults、Chrome Preferences(`color_scheme(2)=0`)
- [x] 5. 取 xdg-desktop-portal-kde 6.6.4 源码(invent.kde.org)确认判定逻辑(QPalette 亮度)
- [x] 6. DBus 抓包 `SettingChanged`(dbus-monitor + 双向切换)——portal 实时准确
- [x] 7. 真实 Chrome 验证(临时 profile + `--remote-debugging-port=9333` + CDP WebSocket,`uv run --with websockets`):
  - dark 下启动 → `True`;切 light → `False`(2.5s 内);change 事件 `dark,light` 双向触发
- [x] 8. 排除干扰项:Playwright 环境伪影(恒 light)、profile 粘滞(headless 换 profile 重测)、`gtk-application-prefer-dark-theme`、`gtk-theme-name`
- [x] 9. 还原:桌面 BreezeLight;`gtk-3.0/settings.ini` 的 `gtk-theme-name` 恢复 `Breeze`、`prefer-dark=false`;杀测试浏览器;清 `/tmp/dr-*`

### Phase 2:Chrome 原生暗色调研与本地实测

- [x] 1. 上游调研:UI Light/Dark/Device 设置、`prefers-color-scheme`/`color-scheme` 支持版本、`#enable-force-dark` 生命周期(123→136→今)、MV2 退场时间线、Dark Reader 维护/隐私/痛点一手 issue、替代品矩阵(Dark Reader / force-dark / Midnight Lizard / Night Eye / Stylus)
- [x] 2. 核对 Linux 152 `chrome://settings/appearance` 实际形态:无 Light/Dark/Device 行,有 Theme 下拉
- [x] 3. `chrome://flags` 深度 DOM 文本抽取:确认 `#enable-force-dark` 在 stable 152 存在(`kOsAll` 与上游源码一致)
- [x] 4. 自建测试页 + `--enable-features=WebContentsForceDark` 截图评测质量(照片不反色、卡片/按钮翻转正确)
- [x] 5. snap Chromium + `--load-extension` 加载 DR 4.9.129 对照(dynamic 默认档生效)
- [x] 6. 截图存档 `screenshots/`(baseline / forcedark / darkreader / flags / settings-appearance)
- [x] 7. 汇总为 `upstream-research.md`(18 条事实速查表 + 本地实测)

### Phase 3:per-site 排除名单落地

- [x] 1. 复制 Chrome History(SQLite)副本,按注册域聚合近 180 天 `visit_count`,过滤噪声域,取前 ~26 站
- [x] 2. 从历史中为每个域挑选代表页面(排除登录/跳转类 URL)
- [x] 3. 确认本地代理 `127.0.0.1:10809` 对境内外站点均可用
- [x] 4. **Pass 1**(`probe_theme.py`):临时 profile 真实 Chrome + CDP,页面加载后实时切换 `Emulation.setEmulatedMedia`,采样背景亮度 → 5 站翻转
- [x] 5. 识别 Pass 1 的假阴性问题(只在加载时读配色的站),并发现 bilibili 崩连接污染了后续数据
- [x] 6. **Pass 2**(`probe_theme2.py`):暗色模拟下全新加载 + 每站独立连接 + 崩溃自动重启 + 超时重试 → 再得 6 站
- [x] 7. 补测 bilibili 视频内页 / gemini / apple 商店页,均无原生暗色
- [x] 8. 解析 DR 现有配置:定位到 `Sync Extension Settings`,写 LevelDB WriteBatch 解析器(`parse_sync.py`),还原键名位移与跨 batch 值分裂,得到 23 字段完整配置
- [x] 9. 合并生成导入文件(`merge.py`):`disabledFor` 填入 11 站,重建 4 条内置 customThemes,其余字段原样保留
- [x] 10. 按 DR `validateSettings()` 规则模拟校验:23 必需字段齐全、类型正确 → PASS
- [x] 11. 交付到 `~/Downloads/darkreader/`(含变更前备份),用户经 **More → Manage settings → Import Settings** 导入成功
- [x] 12. 清理:删除历史库副本、扩展数据库副本、测试 profile;关闭测试浏览器(用户 Chrome 全程未动)
- [x] 13. 归档本目录并脱敏(公开仓库),commit
- [x] 14. 合并三个同日档案(darkreader-system-color-scheme / chrome-native-dark-mode-research / darkreader-per-site-exclusions)为本目录,内部链接与 README 索引同步更新

## 本目录文件

| 文件 | 说明 |
|---|---|
| `spec.md` | 三阶段总设计:Phase 1 警告调查 + Phase 2 摘要 + Phase 3 per-site 排除 |
| `implementation.md` | 本文件 |
| `upstream-research.md` | Phase 2 完整调研报告(官方文档 / Chromium 源码 / 替代品对比 + 本地实测) |
| `screenshots/` | Phase 2 本地实测截图(baseline / forcedark / darkreader / flags / settings-appearance) |
| `Dark-Reader-Settings.json` | Phase 3 导入文件(**已脱敏**;真实文件在 `~/Downloads/darkreader/`) |
| `probe-results-pass2.json` | Pass 2 原始数据(亮度 + 判定) |
| `probe_theme.py` | Pass 1 探测脚本(实时翻转) |
| `probe_theme2.py` | Pass 2 探测脚本(暗色全新加载 + 崩溃恢复) |
| `parse_sync.py` | DR sync LevelDB `.log` 解析器 |
| `merge.py` | 合并生成导入 JSON |

## 回退方式

导入 `~/Downloads/darkreader/Dark-Reader-Settings-BACKUP-before.json`(变更前配置,`disabledFor` 为空)。
或在 DR 设置里逐站移除 Site list 条目。

## 注意事项(给未来的自己)

- **验证 `prefers-color-scheme` / 站点配色行为必须用真实 Chrome + CDP**(临时 profile + `--remote-debugging-port`),不要用 Playwright MCP 浏览器——该环境下恒报 light(2026-08-26 实测,疑似其 flag/环境影响 LinuxUi 初始化)。
- **`pkill -f` 会误杀自己**:命令行快照含相同字符串时会自杀(exit 144),用 `[]` 括号写法(如 `debugging-port=933[5]`、`ms-playwright[-]mcp`)。
- **品牌 Chrome(stable/beta)已忽略 `--load-extension`**(加载后扩展列表为空)——扩展注入类实验必须用 Chromium/Chrome for Testing;snap Chromium 还读不到 `~/.config` 下隐藏路径的扩展目录,需复制到非隐藏路径;扩展默认不碰 `file://` 页面,测试页要走 localhost HTTP。
- **DR 导入是整体覆盖**:必须提交完整 23 字段,只给 `disabledFor` 会重置其余设置(`validateSettings()` 对缺失字段回落 `DEFAULT_SETTINGS`)。
- **`syncSettings: true` 时导入会同步到同账号其他 Chrome**,改动前需确认这是期望行为。
- 复杂引号嵌套的 shell 命令容易触发工具参数编码问题,改用 heredoc 写脚本文件更稳。
- 用户 Chrome 当时运行 151、磁盘已 152:升级待重启属正常现象,与本案无关。

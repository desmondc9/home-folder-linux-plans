# 实施记录 — Dark Reader per-site 排除名单

**结果类型**: 浏览器扩展配置变更(经官方导入),附实测脚本。

## 步骤

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

## 本目录文件

| 文件 | 说明 |
|---|---|
| `design.md` | 方法、判定标准、实测结果、踩坑 |
| `implementation.md` | 本文件 |
| `Dark-Reader-Settings.json` | 导入文件(**已脱敏**;真实文件在 `~/Downloads/darkreader/`) |
| `probe-results-pass2.json` | Pass 2 原始数据(亮度 + 判定) |
| `probe_theme.py` | Pass 1 探测脚本(实时翻转) |
| `probe_theme2.py` | Pass 2 探测脚本(暗色全新加载 + 崩溃恢复) |
| `parse_sync.py` | DR sync LevelDB `.log` 解析器 |
| `merge.py` | 合并生成导入 JSON |

## 回退方式

导入 `~/Downloads/darkreader/Dark-Reader-Settings-BACKUP-before.json`(变更前配置,`disabledFor` 为空)。
或在 DR 设置里逐站移除 Site list 条目。

## 注意事项(给未来的自己)

- **验证站点配色行为必须用真实 Chrome + CDP**,不要用 Playwright MCP 浏览器(其环境下 `prefers-color-scheme` 恒为 light,2026-08-26 实测)。
- **`pkill -f` 会误杀自己**:命令行快照含相同字符串时会自杀(exit 144),用 `[]` 括号写法如 `debugging-port=933[5]`。
- **DR 导入是整体覆盖**:必须提交完整 23 字段,只给 `disabledFor` 会重置其余设置。
- **`syncSettings: true` 时导入会同步到同账号其他 Chrome**,改动前需确认这是期望行为。
- 复杂引号嵌套的 shell 命令容易触发工具参数编码问题,改用 heredoc 写脚本文件更稳。

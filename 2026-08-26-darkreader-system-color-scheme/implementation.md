# 实施记录 — Dark Reader 系统配色警告调查

**结果类型**:纯排查验证,无代码/配置变更。本文件记录操作步骤与还原动作。

## 步骤

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
- [x] 10. 归档本目录并提交

## 注意事项(给未来的自己)

- 验证浏览器 `prefers-color-scheme` 行为时**不要用 Playwright MCP 的浏览器**做证据——该环境下恒报 light(2026-08-26 实测,原因未深究,疑似其 flag/环境影响 LinuxUi 初始化)。用临时 profile + CDP 直连真 Chrome。
- `pkill -f 'ms-playwright-mcp'` 会自杀(匹配到当前 shell 的命令行快照),用 `ms-playwright[-]mcp` 括号写法。
- 用户 Chrome 当时运行 151、磁盘已 152:升级待重启属正常现象,与本案无关。

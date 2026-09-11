# opencode TUI 键绑定 WSL 验证 实施记录

> 单步任务(验证+建档),无代码变更:`tui.json` 由灾备恢复落位,本机零修改。

## 任务清单

- [x] 勘察:主 config schema 无 keybinds 字段(`additionalProperties: false`,不可塞)
- [x] 定位:TUI 键绑定走独立 `~/.config/opencode/tui.json`(`TuiConfig.Info.keybinds`)
- [x] 源码确认默认 `app_exit="ctrl+c,ctrl+d,<leader>q"`(sst/opencode `config/keybind.ts`)
- [x] 本地 `tui.json`(恢复件)内容核对:已移除 ctrl+c 退出、input_clear=ctrl+c、messages_copy+ctrl+shift+c
- [x] 1.18.30 兼容验证:JSON 有效 / 键名与二进制内嵌定义一致 / tui.json 加载逻辑存在 / schema URL 200
- [x] 结论:重启 opencode 生效;当前会话(恢复前启动)仍为旧行为,属预期

## 教训

1. opencode 的键绑定不在 `opencode.json`(schema 拒绝未知键,硬失败),而在 `tui.json`——两套 schema 独立
2. Windows Terminal 无选中时 Ctrl+Shift=C 与 Ctrl+C 同发 0x03:opencode 侧"一个键名管两键",改 `app_exit` 即同时解决
3. TUI 配置不热更新:改完必须重启,运行中的会话行为不代表新配置

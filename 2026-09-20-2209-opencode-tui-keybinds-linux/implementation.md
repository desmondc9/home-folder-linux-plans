# opencode TUI 键绑定 Linux 机 实施记录

> 单步任务:新建 `~/.config/opencode/cli.json` + 建档。无代码变更。

## 任务清单

- [x] 勘察:本机 opencode 为 v2.0.10,V1 的 `tui.json` 机制已被 `cli.json` 取代(文档 + 二进制 strings 双确认)
- [x] 确认 V2 键名映射:`app_exit`→`app.exit`、`input_clear`→`prompt.clear`、`messages_copy`→`messages.copy`
- [x] 确认默认 `app.exit` 在 V2 仍为 `ctrl+c,ctrl+d,<leader>q`(与 V1 相同的问题根源)
- [x] 写入 `~/.config/opencode/cli.json`(0644):`app.exit` 移除 ctrl+c、`prompt.clear=ctrl+c`、`messages.copy+ctrl+shift+c`
- [x] 验证:jq 解析通过;三个命令 ID 在 v2.0.10 二进制内均存在(未知 ID 会被拒绝)
- [x] 建档:spec.md 记录 V1↔V2 差异、方案、验证与残余
- [x] 结论:重启 opencode 生效;运行中会话仍为旧行为,属预期

## 教训

1. V2 起 TUI/CLI 偏好与主配置彻底三分:`opencode.json`(服务端/项目)、`cli.json`(终端偏好,含键绑定)、旧 `tui.json` 仅作迁移输入——别再把键绑定塞进 `tui.json`
2. 跨机器复用 plans 方案时,先核对版本:1.18.30 的方案照搬到 2.0.10 会写错文件与键名(文档声明未知 command ID 会被拒绝)
3. 本机无旧配置时直接写 V2 原生格式,不依赖启动时自动迁移,避免产生"迁移产物 vs 手写"的来源混淆

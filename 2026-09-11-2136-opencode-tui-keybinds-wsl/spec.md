# opencode TUI 键绑定(取消 ctrl+c / ctrl+shift+c 退出)设计规格

- 日期:2026-09-11 21:36
- 环境:WSL2 Ubuntu 26.04(宿主 Windows 11 物理机 DESKTOP-J7NBNU4,mirrored networking)
- 状态:验证完成(配置随灾备恢复已就位,本次为验证与建档)
- 目标机器:WSL Ubuntu(DESKTOP-J7NBNU4),opencode 1.18.30(`~/.opencode/bin/opencode`)

## 1. 背景与问题

opencode TUI 默认 `app_exit` 绑定 `"ctrl+c,ctrl+d,<leader>q"`(源码 `packages/tui/src/config/keybind.ts`),ctrl+c 直接退出。Windows Terminal 无选中文本时,Ctrl+C 与 Ctrl+Shift+C 均向应用发送 0x03(即同一 "ctrl+c" 键事件)——所以两键都会触发退出,误按丢会话。

## 2. 方案(源自原机,随 2026-09-11 灾备恢复落位)

opencode 主配置 schema(`https://opencode.ai/config.json`)**不含**键绑定字段且拒绝未知键;TUI 键绑定在**独立配置文件** `~/.config/opencode/tui.json`(schema `https://opencode.ai/tui.json`,`TuiConfig.Info` 定义 `keybinds: KeybindOverrides`,值支持字符串/数组/KeyStroke 对象/`"none"`/`false`)。

本机 `~/.config/opencode/tui.json`(原机调整后随快照恢复,本次验证有效):

```json
{
  "$schema": "https://opencode.ai/tui.json",
  "keybinds": {
    "app_exit": "ctrl+d,<leader>q",
    "input_clear": "ctrl+c",
    "messages_copy": ["<leader>y", "ctrl+shift+c"]
  }
}
```

语义:
- `app_exit` 从默认中移除 `ctrl+c` → ctrl+c(及同码的 ctrl+shift+c)不再退出;退出只剩 `ctrl+d` 与 `<leader>q`(leader 默认 ctrl+x)
- `input_clear: "ctrl+c"` → ctrl+c 改为清空输入框(默认行为,显式声明)
- `messages_copy` 附加 `ctrl+shift+c` → 支持 kitty 键盘协议的终端下 ctrl+shift+c 语义为复制消息

## 3. 验证(2026-09-11,opencode 1.18.30)

1. `tui.json` JSON 有效;3 个键名(`app_exit`/`input_clear`/`messages_copy`)与 1.18.30 二进制内嵌的键定义一致(strings 抽查命中)
2. 二进制含 `tui.json` 加载逻辑(项目级 `.opencode/tui.json` + 全局 config 目录)
3. schema URL `https://opencode.ai/tui.json` 可达(200)

## 4. 生效条件(关键)

TUI 配置**仅启动时加载,不热更新**——当前正在运行的 opencode 会话(启动于灾备恢复之前)仍持旧绑定。**重启 opencode 后生效**。新会话中验收:ctrl+c 清空输入、ctrl+shift+c 复制消息(或不触发)、退出仅 ctrl+d / ctrl+x,q。

## 5. 已知残余

- 若终端不支持 kitty 键盘协议(WSL 下 Windows Terminal 常规模式),ctrl+shift+c 与 ctrl+c 同码,表现为清空输入——符合"不退出"的目标
- 误按 ctrl+d 仍会退出(保留作兜底退出通道);若也要移除,把 `app_exit` 改为仅 `"<leader>q"`

## 6. 参考

- 源码:`packages/tui/src/config/keybind.ts`(Definitions/默认值)、`config/index.tsx`(TuiConfig.Info)
- customize-opencode 技能(config 变更需重启生效的提醒)

# opencode TUI 键绑定(禁止 ctrl+c 退出)Linux 机设计规格

- 日期:2026-09-20 22:09
- 环境:Linux 桌面机(KDE/Konsole),opencode v2.0.10(`~/.opencode/bin/opencode`)
- 状态:已实施,重启 opencode 后生效
- 前置方案:[2026-09-11-2136-opencode-tui-keybinds-wsl](../2026-09-11-2136-opencode-tui-keybinds-wsl/spec.md)(WSL 机,opencode 1.18.30)

## 1. 背景与问题

opencode TUI 默认 `app.exit` 绑定 `ctrl+c,ctrl+d,<leader>q`,ctrl+c 直接退出,误按丢会话。WSL 机已于 2026-09-11 修复;本机(Linux 桌面)为新落机,需按同样语义重新落地。

## 2. V2 与 V1 的关键差异(本次勘测确认)

本机 opencode 为 **v2.0.10**,与 WSL 方案的 1.18.30 不同,配置机制已变:

| 维度 | V1(WSL 方案) | V2(本机) |
|---|---|---|
| 配置文件 | `~/.config/opencode/tui.json` | `~/.config/opencode/cli.json` |
| schema | `https://opencode.ai/tui.json` | `https://opencode.ai/v2/cli.json` |
| 键名 | `app_exit` / `input_clear` / `messages_copy` | 点分命名:`app.exit` / `prompt.clear` / `messages.copy` |
| 兼容性 | — | V2 启动时自动把旧 `tui.json` 迁移为 `cli.json`(二进制内嵌 `cli.config.migrate` 逻辑,键名经 `F` 映射表转换) |

依据:官方 V2 文档 <https://opencode.ai/v2/docs/cli/keybinds>(`app.exit` 默认仍为 `ctrl+c,ctrl+d,<leader>q`;`prompt.clear` 默认 `ctrl+c`)+ 本机二进制 strings 抽查(三个新键名均存在,未知 ID 会被拒绝)。

因本机无任何历史 `tui.json`/`cli.json`,**直接写 V2 原生格式**,不依赖迁移。

## 3. 方案

`~/.config/opencode/cli.json`(0644,与 WSL 方案逐条等价):

```json
{
  "$schema": "https://opencode.ai/v2/cli.json",
  "keybinds": {
    "app.exit": "ctrl+d,<leader>q",
    "prompt.clear": "ctrl+c",
    "messages.copy": ["<leader>y", "ctrl+shift+c"]
  }
}
```

语义(与 WSL 方案一致):
- `app.exit` 移除 `ctrl+c` → ctrl+c 不再退出;退出只剩 `ctrl+d` 与 `<leader>q`(leader 默认 `ctrl+x`)
- `prompt.clear: "ctrl+c"` → ctrl+c 改为清空输入框(默认行为,显式声明)
- `messages.copy` 附加 `ctrl+shift+c` → 支持 kitty 键盘协议的终端下为复制消息

## 4. 验证(2026-09-20,opencode v2.0.10)

1. `jq` 解析通过,JSON 有效
2. 三个命令 ID(`app.exit`/`prompt.clear`/`messages.copy`)在本机 v2.0.10 二进制 strings 中均命中(文档声明未知 ID 会被拒绝,故此项必要)
3. 文件权限 0644,位于全局 config 目录 `~/.config/opencode/`

## 5. 生效条件(关键)

CLI 配置**仅启动时加载,不热更新**——当前正在运行的 opencode 会话(含本次配置所建的会话)仍持旧绑定,**重启 opencode 后生效**。新会话中验收:ctrl+c 清空输入而非退出;退出仅 `ctrl+d` / `ctrl+x` then `q`。

## 6. 已知残余(与 WSL 方案相同)

- 若终端不支持 kitty 键盘协议,ctrl+shift+c 与 ctrl+c 同码(0x03),表现为清空输入——仍满足"不退出"的目标
- 误按 ctrl+d 仍会退出(保留作兜底退出通道);若也要移除,把 `app.exit` 改为仅 `"<leader>q"`
- V2 中 `<leader>q` 同时是 `session.queued_prompts`(管理排队提示)的默认绑定,与 `app.exit` 保留的 `<leader>q` 并存——沿用 V2 默认的共存行为,未做额外改动

## 7. 性能与容量(性能与容量)

性能门未触发:本任务仅新增一份本地 TUI 配置文件与计划文档,不涉及任何运行时路径、查询、缓存、外部调用或数据处理。

## 8. 参考

- V2 键绑定参考:<https://opencode.ai/v2/docs/cli/keybinds>
- V2 CLI 设置参考:<https://opencode.ai/v2/docs/cli/config>
- 前置方案(WSL/V1):[../2026-09-11-2136-opencode-tui-keybinds-wsl/spec.md](../2026-09-11-2136-opencode-tui-keybinds-wsl/spec.md)

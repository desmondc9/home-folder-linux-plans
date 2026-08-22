# implementation — Konsole 自动切换 rig 拆除

对应 [design.md](./design.md)。

## 任务清单

- [x] 核对 rig 当前状态(path enabled+active、DefaultProfile=Light.profile)
- [x] disable --now path 单元、删除两个 unit 文件、daemon-reload
- [x] konsolerc DefaultProfile 修正为 Dark.profile
- [x] 验证:无残留单元、手动 toggle 三件套健在
- [x] 归档提交 ~/plans

## 变更文件表

| 文件 | 变更 |
|------|------|
| `~/.config/systemd/user/konsole-follow-theme.path` | 删除 |
| `~/.config/systemd/user/konsole-follow-theme.service` | 删除 |
| `~/.config/systemd/user/default.target.wants/konsole-follow-theme.path` | 删除(disable --now 自动移除) |
| `~/.config/konsolerc` | `DefaultProfile=Light.profile` → `Dark.profile` |

未动:konsole-set-theme.sh、Light/Dark profiles、Breeze{Light,Dark}.colorscheme、dev.user.konsole-toggle-theme.desktop、kglobalshortcutsrc 快捷键。

## 验证方式

- [x] `systemctl --user list-unit-files \| grep konsole-follow` → 无输出
- [x] `systemctl --user cat konsole-follow-theme.path` → No files found
- [x] `grep DefaultProfile ~/.config/konsolerc` → Dark.profile
- [x] 手动 toggle 三件套 ls 存在、kglobalshortcutsrc 仍含 konsole-toggle
- [ ] 下次开机 Konsole 默认 Dark(待确认)

## 备注(可迁移经验)

- path 单元在登录早期触发会读到尚未最终落定的 kdeglobals → 主题检测类 rig 应加启动延时/稳定判定,否则开机必误判。
- 拆系统配置 rig 时先读记忆/档案,按"组件清单"逐一核销,拆除后逐项验证(单元、文件、配置值、保留件)。

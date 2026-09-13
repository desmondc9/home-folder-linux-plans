# Implementation: Homebrew 多用户共享配置调查记录

对应 spec.md 的全部范围（单阶段，纯调查，未做任何修改）。

## 依赖

无。

## 任务列表

- [x] 定位 `~/.zshrc` 中与 Homebrew 共享相关的代码：`plugins=(...)` 里的 `brew` 插件、`umask 002`、`brew()` 包装函数（第 130–151 行）。
- [x] 确认 `/opt/homebrew`、`/opt/homebrew/Cellar`、`/opt/homebrew/bin` 的属主/属组/权限：均为 `desmond:homebrew`，`drwxrwxr-x`。
- [x] 确认专用用户组 `homebrew`（gid 503）存在，成员为 `desmond`、`karina`（`dscl . -read /Groups/homebrew`）。
- [x] 确认 `id desmond` / `id karina` 均包含 `503(homebrew)` 及 `80(admin)` 组。
- [x] 确认 `/opt/homebrew` 未设置 setgid 位（`drwxrwxr-x`，非 `drwxrwsr-x`），记录其影响与已有缓解方式。
- [x] 实测 `sudo -n /usr/sbin/chown desmond /opt/homebrew`：返回 `sudo: a password is required`，确认没有配置 NOPASSWD 免密规则，`brew()` 函数中的 `sudo -n` 分支在此机器上必然走到交互式 `sudo` 兜底。
- [x] 检查 `/etc/sudoers.d` 是否有 chown 相关免密规则：无权限读取（`sudo -n` 同样需要密码），间接印证未配置免密。

## 变更文件

无——本任务仅调查记录既有配置，未修改 `~/.zshrc`、用户组、文件权限等任何内容。

## 验证方式

- `dscl . -read /Groups/homebrew`
- `id desmond` / `id karina`
- `ls -ld /opt/homebrew /opt/homebrew/Cellar /opt/homebrew/bin`
- `sudo -n /usr/sbin/chown desmond /opt/homebrew`（验证免密 sudo 是否可用）

## 备注

- 本任务未创建 `git worktree` / 分支 / PR：`~/.zshrc` 及系统用户组/权限不属于任何代码仓库，且本次是纯调查，未做任何变更。
- **待办（本次未处理）**：确认 `karina` 账号的 `~/.zshrc` 是否包含同样的 `umask 002` + `brew()` 包装函数；若缺失，`karina` 直接运行系统 `brew` 在属主冲突时会复现本方案本要规避的失败。建议下次登录 `karina` 账号或请其协助确认后补充记录。
- **教训（可迁移经验）**：多用户共享 Homebrew 单纯"加组 + chmod g+w"并不够——Homebrew 安装包时的 `cp -pR` 之类操作还会受"属主是否匹配当前用户"影响，属组权限只解决"读/写位是否开放"，解决不了"属主对不对"。真正让共享稳定工作的是"运行 brew 前先把整棵目录 chown 给当前用户"这个 wrapper，本质上是"轮流独占属主，靠组权限保证下一个人还能读/写"的策略，而不是真正的"多人同时共同属主"。迁移到新机器时，三层（专用组 + chgrp/chmod + `umask 002` + `brew()` wrapper）要一起搭，缺一层都可能复现"pour bottle 因属主不一致失败"的问题。

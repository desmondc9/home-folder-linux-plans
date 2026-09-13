# macOS 多用户共享同一份 Homebrew 安装

- 日期:2026-07-27(原 mac 档案仅记日期;HHMM 取 mac 仓库入库 commit 时间)
- 环境:macOS(Apple Silicon,/opt/homebrew;双用户 desmond + karina 共享)
- 类型:既有配置调查记录(无 repo 代码变更,无 PR)
- 状态:已完成并验证

## 背景与目标

这台 Mac 上有两个真实用户账号（`desmond`、`karina`），双方都需要用同一份 `/opt/homebrew` 安装（避免每人各装一份，浪费磁盘并导致版本不一致）。目标是记录 `~/.zshrc` 中已经落地的多用户共享方案，说明每一部分解决了什么问题、为什么这样做，方便日后回顾或迁移到其他机器。

本任务是"调查并记录既有配置"，不涉及 `~/CLAUDE.md` 工作流中 Kanban 关联、`git worktree`、Gherkin/E2E、文档同步等环节；仅保留 spec.md / implementation.md 的记录方式（与 [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/)、[claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/)、[podman-compose-provider](./2026-07-30-2027-podman-compose-provider/) 一致）。

## 范围

- **In scope**：调查 `~/.zshrc` 中与 Homebrew 多用户共享相关的配置（`umask`、`brew()` 包装函数）；确认 `/opt/homebrew` 的属主/属组/权限现状；确认 `homebrew` 用户组的成员；确认该方案依赖的 `sudo` 权限现状。
- **Out of scope**：修改现有配置（本次仅调查记录，未发现需要修复的问题）；`karina` 账号自身的 shell 配置是否同步了同样的设置（未调查，见「风险与缓解」）。

## 现状分析

`~/.zshrc` 中与此相关的部分（第 130–151 行）：

```zsh
###############################################################################
#
# 为了共享 homebrew
#
###############################################################################
umask 002

# >>> Homebrew shared wrapper (do not edit) >>>
# 多用户共享 /opt/homebrew：运行 brew 前，先把 /opt/homebrew 的属主切到当前用户。
# 这是为了避免 Homebrew 在 pour bottle 时使用 cp -pR，因目标目录属主不同而失败。
brew() {
  local prefix="/opt/homebrew"
  # 如果 Cellar 下有任何公式的顶层目录不属于当前用户，就先 take ownership
  if find "${prefix}/Cellar" -maxdepth 1 ! -user "$(whoami)" -print -quit 2>/dev/null | grep -q .; then
    sudo -n /usr/sbin/chown -R "$(whoami)" "${prefix}" 2>/dev/null || sudo /usr/sbin/chown -R "$(whoami)" "${prefix}"
  fi
  command brew "$@"
}
# <<< Homebrew shared wrapper <<<
```

调查系统实际状态，确认这套配置对应以下真实基础设施：

1. **专用的 `homebrew` 用户组**（`dscl . -read /Groups/homebrew`）：`PrimaryGroupID: 503`，成员为 `desmond`、`karina` 两个真实用户账号（`id desmond`/`id karina` 均显示 `groups=...,503(homebrew),...`）。这个组不是系统自带的，是专门为共享 Homebrew 创建的。
2. **`/opt/homebrew` 树的属组已改为 `homebrew`，且对组开放写权限**：`ls -ld /opt/homebrew` 显示 `drwxrwxr-x  desmond  homebrew`；`Cellar`、`bin` 等子目录同样是 `homebrew` 组、`rwxrwxr-x` 权限。**注意：没有设置 setgid 位**（权限位是 `rwxrwxr-x` 而非 `rwxrwsr-x`），也就是说新建文件/目录不会自动继承 `homebrew` 属组，而是继承创建者当前进程的属组（一般是 `staff`）。
3. **`umask 002`** 让任何一方在正常 shell 里新建的文件默认带有 `rw-rw-r--`（目录 `rwxrwxr-x`）权限，即"组内成员可写"——这一步保证了"只要文件属组恰好是 `homebrew`"，另一位用户就能读/写，而不会出现 `044`/`022` 那种把组权限锁死成只读的情况。但如「第 2 点」所说，这解决的是**权限位**问题，不解决**属组是谁**的问题。
4. **`brew()` 函数是解决"属主（owner）不一致"问题的关键**：即使 `/opt/homebrew` 组权限开放、`umask` 也配合，Homebrew 内部在"pour bottle"（解压安装预编译包）时会用 `cp -pR`（保留原属主/权限的复制）去写入 `Cellar`。如果目标路径下某些条目的属主是另一个用户（例如上次是 `karina` 装的包，属主是 `karina`），当前用户（`desmond`）即便有组写权限，`cp -p` 在保留属主属性、或后续例如 `chmod`/删除重建等操作时仍可能因为"你不是这个文件的属主"而失败或行为异常（例如无法 `chown` 回自己、无法覆盖设置了限制性权限的旧文件等）。因此该函数在检测到 "Cellar 下存在不属于当前用户的顶层目录" 时，先尝试 `sudo -n chown -R` 静默切换属主（`-n` 表示不交互，若免密不通过就返回失败），失败则退化为普通 `sudo chown -R`（会提示输入密码），把整棵 `/opt/homebrew` 的属主切换成当前登录用户，再执行真正的 `brew` 命令。
5. 实测确认：`sudo -n /usr/sbin/chown ...` 返回 `sudo: a password is required`——即**没有配置 NOPASSWD 免密规则**，`sudo -n` 分支必然失败，实际生效的是"退化为交互式 `sudo`"这条路径。也就是说，每次切换执行 `brew` 的用户和上次不同时，第一次调用 `brew` 会弹出密码提示（除非该 `sudo` 会话时间戳仍然有效）。
6. 该 `brew()` 函数通过 oh-my-zsh 的 `plugins=(... brew)` 插件与自定义 `zshrc` 片段共同生效——`.zshrc` 里 `plugins` 数组包含了官方 `brew` 插件（提供 `brew` 相关补全等），随后又在文件末尾自定义了一个同名 `brew` 的 shell 函数覆盖了普通调用（shell 函数优先于 PATH 上的可执行文件被解析），从而对所有直接键入的 `brew ...` 命令生效。

## 方案总结（三层组合，缺一不可）

| 层 | 解决什么问题 | 具体机制 |
|---|---|---|
| 用户组 `homebrew`（gid 503） | "谁有权限碰 `/opt/homebrew`" | `desmond`、`karina` 都加入该组 |
| 属组 + `umask 002` | "组内成员默认能读写彼此新建的文件" | `/opt/homebrew` 树 `chgrp -R homebrew`（历史一次性操作）+ 组写权限位 + `umask 002` 保证新文件延续组可写 |
| `brew()` 包装函数 | "Homebrew 内部 `cp -pR` 等操作因属主不一致而失败" 的兜底 | 运行真正的 `brew` 前，检测并（必要时交互式 `sudo`）把整棵树 `chown` 给当前用户 |

## 验收标准

- [x] `dscl . -read /Groups/homebrew GroupMembership` 显示 `desmond karina`。
- [x] `ls -ld /opt/homebrew` 属组为 `homebrew`，权限含组写位（`rwxrwxr-x`）。
- [x] `~/.zshrc` 中 `umask 002` 与 `brew()` 包装函数均存在且未被误改（标记为 `do not edit` 的代码块完整）。
- [x] `id desmond` / `id karina` 均包含 `homebrew(503)` 组。
- [x] 确认 `sudo -n` 免密不可用（符合"退化为交互式 sudo"的预期行为，非配置缺陷）。

## 风险与缓解

- **没有 setgid 位**：理论上如果某天有人在 `/opt/homebrew` 树内部用非 `brew` 命令（例如手动 `mkdir`/`cp` 且当前 umask 被改过）新建文件，且其有效 gid 恰好不是 `homebrew`，新文件属组会是该用户的默认组（如 `staff`），另一方可能无权限读写。缓解：日常操作都通过 `brew()` 包装函数或 Homebrew 自身完成，此函数已经用"运行前强制 chown 给当前用户"的方式规避了"属组飘走"带来的实际后果——即便属组不是 `homebrew`，只要属主是当前用户，当前用户自己肯定能操作；等换另一人运行 `brew` 时该函数会再 chown 一次。真正会出问题的场景仅限于"绕开 `brew()` 包装函数、直接用系统自带的 `/opt/homebrew/bin/brew`（例如脚本里写死绝对路径）"。
- **未免密的 `sudo`**：每次两人交替运行 `brew` 且 sudo 时间戳过期时，会有一次密码交互，非自动化场景可接受；若希望完全无人值守（例如 CI 脚本调用 `brew`），需要额外配置 `/etc/sudoers.d` 的 `NOPASSWD: /usr/sbin/chown` 规则（当前未配置，属于有意保守的选择，避免免密 chown 带来的权限扩大风险）。
- **`karina` 账号的 `~/.zshrc` 是否有同样的 `umask 002` + `brew()` 包装**：本次调查只读取了 `desmond` 的 `~/.zshrc`，未登录 `karina` 账号核实其配置是否一致。若 `karina` 的 shell 里没有这个包装函数，她直接调用系统 `brew` 命令在属主不一致时会遇到本方案本来要规避的报错。**待办**：确认/同步 `karina` 账号下的 `~/.zshrc`。
- **两人是否都在系统层面属于 `admin` 组（能执行需要密码的 `sudo`）**：已确认 `desmond`、`karina` 的 `id` 输出均含 `80(admin)`，具备执行 `sudo chown` 的权限前提，方案对两人均可生效。

## 参考

- `~/.zshrc` 第 130–151 行（Homebrew shared wrapper 代码块）。
- `dscl . -read /Groups/homebrew`、`id desmond`、`id karina` 的实测输出。
- [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/)、[claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/)、[podman-compose-provider](./2026-07-30-2027-podman-compose-provider/)（同类"单机环境配置记录"格式参考）

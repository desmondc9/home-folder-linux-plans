# ~/CLAUDE.md 从 Linux 迁移到 macOS 的兼容性审计

- 日期:2026-07-30(原 mac 档案仅记日期;HHMM 取 mac 仓库入库 commit 时间)
- 环境:macOS(~/CLAUDE.md 自 Linux 机器拷贝后的兼容性审计)
- 类型:配置文件审计与修正(无 repo 代码变更,无 PR)
- 状态:已完成并验证

## 背景与目标

用户的 `~/CLAUDE.md`（Claude Code 的全局项目指令）是从一台 Linux 机器上直接拷贝过来的，尚未针对这台 macOS 机器做过校验。目标：逐条核实文件里提到的工具/路径/机制在这台 Mac 上是否真的成立，把不成立的部分换成 mac 上可信的等价方案，并把改动前后的版本、审计过程记录下来。

本任务是"审计既有配置文件并按需修正"，不涉及 `~/CLAUDE.md` 工作流本身描述的 Kanban 关联、`git worktree`、Gherkin/E2E、PR 提交等环节（这些环节是给"代码仓库内的功能开发"用的，本任务的对象就是 `~/CLAUDE.md` 这份文件本身）；仅保留 spec.md / implementation.md 的记录方式（与 [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/)、[claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/)、[podman-compose-provider](./2026-07-30-2027-podman-compose-provider/)、[homebrew-multiuser-shared](./2026-07-27-2027-homebrew-multiuser-shared/)、[java-sdkman-migration](./2026-07-30-2027-java-sdkman-migration/) 一致）。

## 范围

- **In scope**：逐条核实 `~/CLAUDE.md` 中「Preferred CLI tools」「Network access from mainland China」两节涉及的具体命令/二进制名/文件路径在这台 Mac 上是否成立；修正确认不成立的内容；确保修正后的表述与本次会话里已经验证过的实际环境状态（[podman-compose-provider](./2026-07-30-2027-podman-compose-provider/) 里 `podman compose` 走 `docker-compose` 后端的结论）保持一致。
- **Out of scope**：`~/CLAUDE.md` 中「Development, testing, & debugging workflow」章节描述的是一套通用的多仓库开发流程规范（monorepo + submodule + worktree + Gherkin/E2E），其内容本身与操作系统无关，不涉及具体 mac/linux 二进制差异，未做改动；文件中出现的 `voice-input-linux` 仅是目录命名规则的示例文本，不是技术性断言，未改动。

## 现状分析（逐条核实结果）

对 `~/CLAUDE.md` 的两个小节做了逐条实测：

### 「Preferred CLI tools」

| 条目 | 断言 | 实测结果 | 结论 |
|---|---|---|---|
| ripgrep | 二进制名 `rg` | `which rg` → `/opt/homebrew/bin/rg`（15.2.0） | ✅ 成立，无需改 |
| fd | 文中写的是 `fdfind` | `which fdfind` → 找不到；`which fd` → `/opt/homebrew/bin/fd`（10.4.2） | ❌ **不成立**，需修正 |
| sd | 二进制名 `sd` | `which sd` → `/opt/homebrew/bin/sd`（1.0.0） | ✅ 成立，无需改 |
| jq | 二进制名 `jq` | `which jq` → `/opt/homebrew/bin/jq`（1.8.2） | ✅ 成立，无需改 |
| uv | 已安装 | 此前多个任务中已验证（见 [claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/)） | ✅ 成立，无需改 |
| npm | 已安装 | 此前多个任务中已验证 | ✅ 成立，无需改 |
| podman | 已安装，优先于 docker | 此前已验证并做过 [podman-compose-provider](./2026-07-30-2027-podman-compose-provider/) | ✅ 成立，无需改 |

**`fdfind` 问题的根因**：这是 Debian/Ubuntu 系发行版的命名方式——因为 `fd` 这个包名在 Debian 仓库里已经被另一个无关工具占用，Debian 的 `fd-find` 包只能把可执行文件装成 `fdfind` 以避免冲突。macOS 上通过 Homebrew 安装的 `fd` 包没有这个历史包袱，二进制直接叫 `fd`。这是一条典型的"抄错了具体细节，但没抄错工具选型"的 Linux→Mac 迁移坑——工具本身（fd）选对了，只是二进制名字抄了 Linux 发行版特有的别名。

### 「Network access from mainland China」

| 条目 | 断言 | 实测结果 | 结论 |
|---|---|---|---|
| 本地代理 `127.0.0.1:10809` | 代理服务可用 | 此前 [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/) 已验证代理服务本身在这台机器上正常工作 | ✅ 成立，无需改 |
| `/etc/systemd/system/docker.service.d/http-proxy.conf` | 用于给"忽略 shell 环境变量的服务"配代理 | `which systemctl` 找不到；`/etc/systemd` 目录不存在 | ❌ **不成立**，macOS 没有 systemd |
| `~/.docker/config.json` | Docker CLI 配置文件路径 | 该路径本身是 Docker CLI 的标准配置位置，跨平台通用（Docker Desktop for Mac / Linux 均适用） | ✅ 路径本身成立，保留 |

**systemd 问题的根因**：macOS 用的是 `launchd`，从来没有 systemd。这条路径是原样从 Linux 机器上抄过来的具体范例，在 mac 上没有对应文件，属于"举例失效"而非"原则失效"——原则（有些服务不认 shell 里的环境变量，需要单独配置）依然成立，只是需要换一个 mac 上真实存在的例子。同时考虑到这台机器用 Podman（而不是 Docker daemon），Podman 的实际守护进程运行在 `podman machine` 起的一个独立 Linux 虚拟机里，和 macOS 宿主机是两个独立的网络命名空间——这一点在 [podman-compose-provider](./2026-07-30-2027-podman-compose-provider/) 的风险小节里已经记录过（宿主机代理不会自动透传进 VM），这里顺带把这个已知事实也写进了修正后的范例里。

### 顺带发现的表述冲突（非 Linux/Mac 不兼容，但需要一并修正）

`~/CLAUDE.md` 第 182 行（E2E 测试步骤示例）写的是：

```bash
podman compose up -d      # or podman-compose up -d
```

这与本次会话在 [podman-compose-provider](./2026-07-30-2027-podman-compose-provider/) 里的结论直接矛盾——用户明确反馈 Python 版 `podman-compose` 运行时"奇奇怪怪的问题"，已经特意确认并固定 `podman compose` 走 `docker-compose` 作为 provider。继续在 `~/CLAUDE.md` 里把 `podman-compose` 列为等价备选，会让以后的自己（或 AI）重新踩回这个坑，因此一并删除该备选项。

## 解决方案

对 `~/CLAUDE.md` 做三处最小化修改：

1. **第 8 行**：`**fd** (`fdfind`) is installed` → 改为 `**fd** is installed`，并加括注说明 `fdfind` 是 Debian/Ubuntu 特有命名，macOS Homebrew 上二进制就是 `fd`。
2. **第 55 行**：把 `/etc/systemd/system/docker.service.d/http-proxy.conf` 这个 Linux-only 范例，替换成 macOS 上真实成立的等价方案——`launchd` 服务 `.plist` 里的 `EnvironmentVariables`，以及针对 Podman 的特殊情况（守护进程在 `podman machine` 的 VM 里，需要用 `podman machine ssh` 进 VM 内部单独配置代理，而不是指望 `~/.zshrc` 里的导出能透传进去）。
3. **第 182 行**：删除 `# or podman-compose up -d` 备选项，只保留 `podman compose up -d`，与 [podman-compose-provider](./2026-07-30-2027-podman-compose-provider/) 的结论保持一致。

## 验收标准

- [x] `which fdfind` 在这台机器上找不到，`which fd` 能找到——确认修正前的表述确实不成立，修正后的表述（直接用 `fd`）成立。
- [x] `which systemctl` 与 `/etc/systemd` 均不存在——确认修正前的范例路径确实不成立；`which launchctl` 存在，确认修正后引用的 mac 机制真实存在。
- [x] 全文搜索 `systemd|apt-get|apt |yum |dnf |snap install|/etc/init\.d|fdfind|xdg-open|\.deb|\.rpm` 等 Linux 专属关键词，修正后仅剩历史遗留的示例目录名 `voice-input-linux`（非技术断言，不影响功能，未改动）。
- [x] 修正后的 `podman compose up -d` 表述与 [podman-compose-provider](./2026-07-30-2027-podman-compose-provider/) 的结论一致，不再有矛盾的备选写法。
- [x] 修正前对 CLI 工具的核实覆盖了「Preferred CLI tools」小节列出的全部 7 个工具，「Network access」小节涉及的全部路径/机制。

## 风险与缓解

- **本次审计范围仅覆盖了「Preferred CLI tools」与「Network access from mainland China」两节**：「Development, testing, & debugging workflow」章节内容与操作系统无关（monorepo/worktree/Gherkin 概念在 mac/linux 上等价），未逐条实测，但也没有发现任何 Linux 专属路径或命令，风险很低。
- **`~/CLAUDE.md` 未来若继续被拷贝到其他 Linux 机器使用**：本次修正是"面向这台 Mac"的，如果之后要把同一份文件反向搬回 Linux 环境，`fd`/`launchd` 相关的两处措辞需要再切换回去（或者写成同时兼容两边的表述）。鉴于当前该文件明确是这台 Mac 专用的项目指令（`~/CLAUDE.md`，非仓库内共享文件），暂不处理跨机器兼容性，仅在此记录以防未来遗忘。

## 后续补充：安装 CLAUDE.md 引用的工具（tmux）

审计完成、修正合并后，用户要求把 `~/CLAUDE.md` 里提到的工具都通过 Homebrew 装好。逐一核对：

- 「Preferred CLI tools」列出的 7 个工具（ripgrep/fd/sd/jq/uv/npm/podman）在本次审计里已经逐条实测过，全部已安装——其中 `rg`/`fd`/`sd`/`jq`/`podman` 5 个是 Homebrew 装的（`brew list --formula` 可见），`uv`/`npm` 按现有约定分别由 uv 自身安装器和 nvm 管理，**不应该**改成 brew 装（否则会和已经确认可用的 nvm node 版本管理机制冲突，参见 [claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/) 里 Node/Python/Java 各自管理方式的结论）。
- 「tmux-aware subagent display」一节引用了 `tmux` 命令，但只是"检测是否在 tmux 里"的条件逻辑，原文没有断言"tmux is installed"。实测 `which tmux` 发现确实没装——这意味着该节描述的并行 agent 可视化能力目前完全不可用（不是"表现降级"，是"功能不存在"）。
- 按 `~/CLAUDE.md`「Overview」的总原则（工具不存在时优先安装而非退化），补装 `brew install tmux`（3.7b，含 `libevent` 依赖）。

这一步不涉及修改 `~/CLAUDE.md` 文本本身——原文没有错误断言，只是引用的工具当时没装；现在装上之后，原文描述才算真正生效。

## 参考

- `~/CLAUDE.md`（修正后的完整内容已拷贝一份存档在本任务目录下的 `CLAUDE.md`）。
- [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/)（本地代理服务可用性的既有验证结论）
- [podman-compose-provider](./2026-07-30-2027-podman-compose-provider/)（`podman compose` provider 选择的既有结论，本次据此删除了 `podman-compose` 备选表述）
- [claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/)、[homebrew-multiuser-shared](./2026-07-27-2027-homebrew-multiuser-shared/)、[java-sdkman-migration](./2026-07-30-2027-java-sdkman-migration/)（同类"单机环境配置记录"格式参考）

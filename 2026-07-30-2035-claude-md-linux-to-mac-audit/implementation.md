# Implementation: ~/CLAUDE.md 从 Linux 迁移到 macOS 的兼容性审计

对应 spec.md 的全部范围（单阶段）。

## 依赖

依赖此前已完成的 [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/)（代理服务可用性）与 [podman-compose-provider](./2026-07-30-2027-podman-compose-provider/)（`podman compose` provider 选择结论）的验证结果，本任务直接复用而非重新验证。

## 任务列表

- [x] 通读 `~/CLAUDE.md` 全文，定位涉及具体二进制名 / 文件路径 / 机制名称的表述（「Preferred CLI tools」「Network access from mainland China」两节）。
- [x] 逐条实测「Preferred CLI tools」：`which rg`/`which fd`/`which fdfind`/`which sd`/`which jq`，确认 `fdfind` 在这台 Mac 上不存在（`fd` 才是正确二进制名）。
- [x] 实测「Network access」：`which systemctl`、`ls /etc/systemd`，确认 macOS 没有 systemd；`which launchctl` 确认 `launchd` 才是 mac 对应机制。
- [x] 全文 grep 关键词（`systemd|apt-get|apt |yum |dnf |snap install|/etc/init\.d|fdfind|xdg-open|\.deb|\.rpm|/home/|\.bashrc|\.bash_profile|linux|ubuntu|debian|wsl`），确认除已处理的两处外，仅剩 `voice-input-linux` 这一处示例目录名（非技术断言）。
- [x] 顺带核对 E2E 测试步骤里 `podman compose up -d # or podman-compose up -d` 这行示例，确认与 [podman-compose-provider](./2026-07-30-2027-podman-compose-provider/) 的既有结论矛盾。
- [x] 修正 `~/CLAUDE.md` 第 8 行：`fdfind` → `fd`，并加括注说明命名差异的历史原因。
- [x] 修正 `~/CLAUDE.md` 第 55 行：`/etc/systemd/system/docker.service.d/http-proxy.conf` 替换为 macOS `launchd` `.plist` `EnvironmentVariables` + Podman VM（`podman machine ssh`）内部单独配置代理的范例。
- [x] 修正 `~/CLAUDE.md` 第 182 行：删除 `# or podman-compose up -d` 备选表述。
- [x] 对 `~/CLAUDE.md` 做敏感信息扫描（`pactera|centific|password|secret|token|api[_-]?key`），确认无匹配后再拷贝进将要推送到公开仓库的 `~/plans`。
- [x] 将修正后的 `~/CLAUDE.md` 拷贝一份存档到本任务目录 `~/plans/006-claude-md-linux-to-mac-audit/CLAUDE.md`。

## 后续补充任务：安装 CLAUDE.md 引用的工具

- [x] 重新核对「Preferred CLI tools」7 个工具的安装状态：`which rg/fd/sd/jq/uv/npm/podman` 全部命中；`brew list --formula | grep -xE 'ripgrep|fd|sd|jq|uv|npm|podman|node|tmux'` 确认 `fd`/`jq`/`podman`/`ripgrep`/`sd` 是 brew 装的，`uv`/`npm` 不是（按设计分别由 uv 自身安装器/nvm 管理，未改动）。
- [x] 核对「tmux-aware subagent display」一节引用的 `tmux`：`which tmux` 确认未安装。
- [x] `brew install tmux`（连带依赖 `libevent`）。
- [x] 验证：`which tmux` → `/opt/homebrew/bin/tmux`；`tmux -V` → `tmux 3.7b`。

## 变更文件

| 文件 | 变更内容 |
|------|----------|
| `~/CLAUDE.md` | 第 8 行 `fdfind`→`fd`（加历史原因括注）；第 55 行系统 systemd 范例换成 macOS `launchd`/`podman machine` 范例；第 182 行删除 `podman-compose` 备选表述 |
| `~/plans/006-claude-md-linux-to-mac-audit/CLAUDE.md`（新建） | 修正后 `~/CLAUDE.md` 的存档拷贝，用于版本追溯 |
| Homebrew | 新增安装 `tmux`（3.7b，连带依赖 `libevent`），补齐 `~/CLAUDE.md` 引用但此前未安装的工具 |

未涉及任何代码仓库文件、API、数据库变更；`~/CLAUDE.md` 本身不属于任何 git 仓库（用户主目录下的全局配置文件），本次改动直接生效于文件本身，不需要额外部署步骤。

## 验证方式

- `which fdfind`（应找不到）/ `which fd`（应找到）。
- `which systemctl`、`ls /etc/systemd`（均应找不到）/ `which launchctl`（应找到）。
- `grep -niE "systemd|apt-get|...|fdfind|..." ~/CLAUDE.md`：确认修正后除示例目录名外无 Linux 专属残留。
- 人工比对 `~/CLAUDE.md` 第 182 行与 [podman-compose-provider](./2026-07-30-2027-podman-compose-provider/) spec.md 的解决方案章节，确认表述一致。

## 备注

- 本任务未创建 `git worktree` / 分支 / PR：`~/CLAUDE.md` 是用户主目录下的全局配置文件，不属于任何代码仓库，`~/CLAUDE.md` 工作流本身描述的 Kanban/worktree/Gherkin/PR 环节是给"仓库内功能开发"用的，不适用于审计这份文件自身。
- **教训（可迁移经验）**：跨发行版/跨操作系统迁移配置文件时，最容易出问题的不是"要不要用某个工具"这个决策层面（这一层通常是对的），而是"这个工具在当前系统上到底叫什么名字、配置文件在哪"这种执行细节层面——`fd` vs `fdfind` 就是典型例子：工具选型完全正确，但抄录了源系统（Debian/Ubuntu）特有的二进制别名。审计这类文件时，应该对每一个具体的命令名/路径都实际 `which`/`ls` 一遍，而不是只检查"这个工具的概念在目标系统上是否存在"。
- 本任务产出的 spec.md/implementation.md/CLAUDE.md 存档，与 `~/CLAUDE.md` 本身一起，会作为 `~/plans` 这个 git 仓库的一部分推送到 `desmondc9/home-folder-mac-plans`（公开仓库）。

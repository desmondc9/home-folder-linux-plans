# Java 版本管理迁移到 SDKMAN

- 日期:2026-07-30(原 mac 档案仅记日期;HHMM 取 mac 仓库入库 commit 时间)
- 环境:macOS(SDKMAN 接管 Homebrew openjdk@21)
- 类型:本机工具链迁移(无 repo 代码变更,无 PR)
- 状态:已完成并验证

## 背景与目标

此前排查发现（见 [claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/) 的调查结论），这台机器上 Node 用 nvm 管理、Python 是 Homebrew + uv 双轨，唯独 Java 是"直接装 Homebrew 的 `openjdk@21`，`JAVA_HOME`/`PATH` 手写在 `~/.zshrc` 里，没有任何版本切换工具"。用户要求引入 SDKMAN 管理 Java，并把 Homebrew 装的那份 JDK 迁移过去。

本任务为本机工具链环境配置，非某个代码仓库内的功能开发，因此不涉及 `~/CLAUDE.md` 工作流中 Kanban 关联、`git worktree`、Gherkin/E2E、文档同步等环节；仅保留 spec.md / implementation.md 的记录方式（与 [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/)、[claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/)、[podman-compose-provider](./2026-07-30-2027-podman-compose-provider/)、[homebrew-multiuser-shared](./2026-07-27-2027-homebrew-multiuser-shared/) 一致）。

## 范围

- **In scope**：安装 SDKMAN；将 Java 版本管理权从"手写 `~/.zshrc` + Homebrew"迁移到 SDKMAN；处理 Homebrew 装的 `openjdk@21`（用户实际在用的开发版本）；确认迁移不影响 `jdtls-lsp`（依赖另一个不带版本号的 Homebrew `openjdk` 26.0.2，见 [claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/)）。
- **Out of scope**：Node（nvm）、Python（Homebrew + uv）的管理方式不变，不在本次调整范围内。

## 现状分析 / 关键决策点

1. **SDKMAN 的 "local install" 本质是符号链接，不是真正迁移**：第一次尝试用 `sdk install java <ver> <path>` 把 Homebrew Cellar 里现成的 `openjdk@21` 注册进 SDKMAN，实测结果是 SDKMAN 只在 `~/.sdkman/candidates/java/<id>` 下创建了一个指向 Homebrew Cellar 路径的符号链接，底层文件仍然完全由 Homebrew 拥有——如果之后 `brew uninstall openjdk@21`，SDKMAN 这边会跟着失效。这不是真正的"迁移"，只是"借用"。
2. **征询用户后选择"彻底独立"方案**：让 SDKMAN 重新下载一份独立管理的 JDK 发行版，装到 `~/.sdkman/candidates/java/` 下（真实拷贝，约 330MB+，不是链接），之后可以放心把 Homebrew 那份卸载掉，实现真正的解耦。
3. **发行版选择**：用户偏好 Eclipse Temurin。但 SDKMAN 上 Temurin 目前最新到 `21.0.11`（尚未发布 `21.0.12`），与 Homebrew 原先的 `21.0.12` 差一个 patch 版本。中间一度先装了 Amazon Corretto `21.0.12-amzn`（版本号精确匹配），确认用户偏好后改为卸载 Corretto、安装 Temurin `21.0.11-tem` 并设为默认。
4. **`jdtls-lsp` 的依赖需要单独确认不受影响**：`jdtls` 的启动脚本硬编码 fallback 路径是 `/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home`（对应**不带版本号**的 Homebrew `openjdk` formula，26.0.2），且 `brew uses --installed openjdk` 显示只有 `jdtls` 依赖它——这是另一个独立的 Homebrew 包，和本次迁移/卸载的 `openjdk@21` 无关，因此卸载 `openjdk@21` 不会影响 `jdtls-lsp`。另外，`jdtls` 脚本写的是 `JAVA_HOME="${JAVA_HOME:-<fallback>}"`，只要 shell 里 `JAVA_HOME` 已经被 SDKMAN 设置（且版本 17+），jdtls 会优先使用 SDKMAN 提供的 JAVA_HOME，fallback 路径根本不会被触发。
5. **验证方法踩坑**：一开始用 `zsh -l -c '...'` 验证新 shell 里 `JAVA_HOME` 是否正确，发现输出的还是 Homebrew 旧路径，一度怀疑迁移未生效。排查后发现 `zsh -c`（非交互模式）根本不会 source `~/.zshrc`——`-l`（login）只影响 `.zprofile`/`.zlogin` 等登录相关文件，`.zshrc` 只在**交互式** shell 里被 source。之前看到的"旧值"其实是当时这个终端会话自己进程里从会话开始时就继承下来的残留环境变量，并非重新读取配置的结果。改用 `zsh -i -c '...'`（真正模拟"新开一个交互式终端"）才是正确的验证方式，结果确认 `JAVA_HOME`/`java`/`javac` 均正确指向 SDKMAN。

## 解决方案

1. `curl -s "https://get.sdkman.io" | bash` 安装 SDKMAN（域名可直连，不需要走本地代理）。安装脚本自动在 `~/.zshrc` 末尾追加 init 代码块（SDKMAN 要求必须在文件最后，以保证它在 PATH 竞争中"后到者赢"）。
2. 放弃"符号链接式本地注册"，改用 `sdk install java 21.0.11-tem` 让 SDKMAN 独立下载安装 Temurin 21.0.11，并 `sdk default java 21.0.11-tem` 设为默认版本。
3. 删除 `~/.zshrc` 中手写的 `export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"` 与 `export JAVA_HOME="/opt/homebrew/opt/openjdk@21"` 两行，完全交给 SDKMAN 的 init 脚本管理 `JAVA_HOME`/`PATH`。
4. 确认无其他依赖后，`brew uninstall openjdk@21`，释放约 330MB 磁盘空间；不带版本号的 `openjdk`（26.0.2，`jdtls` 的依赖）保留不动。

## 验收标准

- [x] `sdk current java` 显示 `21.0.11-tem` 为当前默认版本。
- [x] 真正的交互式 shell（`zsh -i -c` 或新开终端）中 `JAVA_HOME` 指向 `~/.sdkman/candidates/java/current`，`java -version`/`javac -version` 输出 Temurin 21.0.11。
- [x] `~/.zshrc` 中不再含有任何指向 `/opt/homebrew/opt/openjdk@21` 的手写 `PATH`/`JAVA_HOME`。
- [x] `brew list --versions | grep openjdk` 只剩不带版本号的 `openjdk`（26.0.2），`openjdk@21` 已卸载。
- [x] 卸载 `openjdk@21` 后，重新用真实 `.java` 测试文件跑 `LSP documentSymbol`，`jdtls-lsp` 依旧正常返回结果，证明其对 `openjdk`（26.0.2）的依赖未受影响。

## 风险与缓解

- **Temurin 版本落后 Homebrew 原版一个 patch（21.0.11 vs 21.0.12）**：JDK patch 版本之间通常只是安全修复和小 bug fix，对日常开发影响可忽略；待 SDKMAN 上架 Temurin `21.0.12` 后可用 `sdk install java 21.0.12-tem && sdk default java 21.0.12-tem` 无痛升级。
- **依赖"SDKMAN init 代码块必须在 `~/.zshrc` 末尾"这一约束**：如果未来有人在 SDKMAN 代码块之后又追加了新的 `PATH`/`JAVA_HOME` 覆盖逻辑（类似本次要清理掉的那种手写导出），会重新把 Java 版本管理权"抢回去"。缓解：以后新增任何 Java 相关 `PATH`/`JAVA_HOME` 配置，一律通过 `sdk install`/`sdk default`/`sdk use`，不要在 `~/.zshrc` 里手写。
- **验证脚本环境（如 CI、非交互式脚本）读取不到 `JAVA_HOME`**：SDKMAN 的 `JAVA_HOME`/`PATH` 设置只在 `.zshrc` 里生效，只有**交互式**shell 才会 source 它；非交互式脚本（`zsh script.sh`、`crontab`、某些 IDE 的"外部工具"执行环境）不会自动获得 SDKMAN 的 Java。若未来有非交互式场景需要用到 Java，需要显式 `source "$HOME/.sdkman/bin/sdkman-init.sh"` 或改用 `~/.zshenv`（对所有 shell 生效，包括非交互式），本次未做此项改动。
- **`jdtls-lsp` 的 fallback JAVA_HOME 依赖不带版本号的 Homebrew `openjdk`（26.0.2）**：本次未迁移这一个，仍由 Homebrew 管理，与本次 SDKMAN 化的 `openjdk@21` 相互独立，不冲突也不重复。

## 参考

- SDKMAN 官网 `https://sdkman.io`。
- [claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/)（Java/TS/Python 版本管理现状排查的起点，及 `jdtls` 对 Homebrew `openjdk` 的依赖细节）
- [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/)、[podman-compose-provider](./2026-07-30-2027-podman-compose-provider/)、[homebrew-multiuser-shared](./2026-07-27-2027-homebrew-multiuser-shared/)（同类"单机环境配置记录"格式参考）

# Implementation: Java 版本管理迁移到 SDKMAN

对应 spec.md 的全部范围（单阶段）。

## 依赖

依赖 [claude-code-lsp-plugins](./2026-07-30-2027-claude-code-lsp-plugins/) 中对 `jdtls`/Homebrew `openjdk` 依赖关系的调查结论（用于判断本次卸载操作是否安全）。

## 任务列表

- [x] 确认 `https://get.sdkman.io` 可直连（`curl -s -o /dev/null -w '%{http_code}'` 返回 200），无需走本地代理。
- [x] 执行 `curl -s "https://get.sdkman.io" | bash` 安装 SDKMAN（5.23.0）；安装脚本自动在 `~/.zshrc` 末尾追加 init 代码块。
- [x] 确认 `jdtls` 的 wrapper 脚本（`/opt/homebrew/bin/jdtls`）fallback JAVA_HOME 硬编码指向 `/opt/homebrew/opt/openjdk/...`（不带版本号），`brew uses --installed openjdk` 确认只有 `jdtls` 依赖它——与将要迁移/卸载的 `openjdk@21` 是两个独立的 Homebrew 包。
- [x] 第一次尝试：`sdk install java 21.0.12-homebrew /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`，`sdk default java 21.0.12-homebrew`。
- [x] 验证发现该 candidate 只是符号链接（`file ~/.sdkman/candidates/java/21.0.12-homebrew` 显示指向 Homebrew Cellar 路径），非真正独立迁移，遂就此征询用户意见。
- [x] 用户确认选择"彻底独立"方案后：`sdk install java 21.0.12-amzn`（Amazon Corretto，版本号精确匹配原 Homebrew 21.0.12），确认为真实拷贝（`du -sh` 336M，非符号链接）。
- [x] `sdk uninstall java 21.0.12-homebrew` 清理掉第一次尝试留下的符号链接 candidate。
- [x] 用户中途改口偏好 Temurin：`sdk install java 21.0.11-tem`（SDKMAN 上 Temurin 最新只到 21.0.11），设为默认；`sdk uninstall java 21.0.12-amzn` 移除之前安装的 Corretto。
- [x] 编辑 `~/.zshrc`：删除 `export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"` 与 `export JAVA_HOME="/opt/homebrew/opt/openjdk@21"` 两行（原第 155–156 行，与 `zoxide init` 那行粘连在一起，一并清理干净）。
- [x] 验证踩坑：先用 `zsh -l -c '...'` 测试，`JAVA_HOME` 仍显示 Homebrew 旧值，一度怀疑迁移未生效。
- [x] 排查确认：`zsh -c`（非交互）不会 source `~/.zshrc`；用 `zsh -x -l -c` 输出 xtrace 到文件也证实几乎没有执行 `.zshrc` 里的内容；改用 `env -i ... source sdkman-init.sh` 单独验证脚本本身逻辑正确；最终用 `zsh -i -c '...'`（交互式）复现"新开终端"场景，确认 `JAVA_HOME`/`java -version`/`javac -version` 均正确指向 SDKMAN 的 Temurin 21.0.11。
- [x] 征询用户是否卸载 Homebrew 的 `openjdk@21`（已无 SDKMAN 依赖，纯冗余）：用户确认卸载。
- [x] `brew uninstall openjdk@21`，释放约 346.7MB。
- [x] 卸载后重新验证：`zsh -i -c` 确认 `JAVA_HOME`/`java -version` 仍正确；用真实 `.java` 测试文件对 `jdtls-lsp` 重跑 `LSP documentSymbol`，确认无回归。
- [x] 清理所有临时测试文件（`HelloAgain.java`、`ztrace.log` 等 scratchpad 文件）。

## 变更文件 / 环境变更

| 变更项 | 内容 |
|------|----------|
| 新增安装 | SDKMAN 5.23.0（`~/.sdkman/`） |
| SDKMAN candidates | `java 21.0.11-tem`（Eclipse Temurin，独立安装，非符号链接，当前默认版本） |
| `~/.zshrc` | 追加 SDKMAN init 代码块（文件末尾，安装脚本自动完成）；删除原 `openjdk@21` 相关的 `PATH`/`JAVA_HOME` 手写导出（原第 155–156 行） |
| Homebrew | 卸载 `openjdk@21`（21.0.12，释放 346.7MB）；保留不带版本号的 `openjdk`（26.0.2，`jdtls-lsp` 依赖，未改动） |

未涉及任何代码仓库文件、API、数据库变更。

## 验证方式

- `sdk current java`：确认当前默认版本。
- `zsh -i -c 'echo $JAVA_HOME; java -version; javac -version'`：模拟真实新开交互式终端，确认版本管理生效（**不要**用 `zsh -c`/`zsh -l -c` 验证，非交互模式不会 source `~/.zshrc`）。
- `brew list --versions | grep openjdk`：确认只剩不带版本号的 `openjdk`。
- 对真实 `.java` 文件执行 `LSP documentSymbol`：确认 `jdtls-lsp` 未受影响。

## 备注

- 本任务未创建 `git worktree` / 分支 / PR：改动对象是本机 shell 配置（`~/.zshrc`）和系统工具链（SDKMAN candidates、Homebrew 包），不属于任何代码仓库内的功能开发。
- **教训（可迁移经验，最重要的一条）**：验证"某个 shell 配置改动是否生效"时，必须用**交互式** shell（`zsh -i -c` 或真正开一个新终端窗口），`zsh -c`/`zsh -l -c` 这类非交互调用根本不会 source `~/.zshrc`，测出来的是调用者当前进程残留的环境变量，不是配置文件本身的效果——这次差点因为这个方法论错误误判"迁移失败"。
- **教训（SDKMAN 相关）**：SDKMAN 的 `sdk install java <ver> <local-path>`（本地注册功能）本质是符号链接，不是拷贝——如果目标是"和原包管理器彻底解耦"，必须让 SDKMAN 从其官方源重新下载安装，而不是注册现有路径。
- 若未来迁移到新机器：`curl -s "https://get.sdkman.io" | bash` → `sdk install java 21.0.11-tem`（或届时 SDKMAN 上已有的最新 Temurin 21.x）→ `sdk default java <version>`，无需再手写 `~/.zshrc` 里的 `JAVA_HOME`/`PATH`（SDKMAN 安装脚本会自动处理，且必须保持在文件末尾）。
- 待办（有意不在本任务处理）：SDKMAN 上架 Temurin `21.0.12` 后，可执行 `sdk install java 21.0.12-tem && sdk default java 21.0.12-tem` 补齐 patch 版本。

# Claude Code 三个 LSP 插件（jdtls-lsp / typescript-lsp / pyright-lsp）排查与修复

- 日期:2026-07-30(原 mac 档案仅记日期;HHMM 取 mac 仓库入库 commit 时间)
- 环境:macOS(Claude Code CLI;jdtls/typescript/pyright 三 LSP 插件)
- 类型:本机工具链修复(无 repo 代码变更,无 PR)
- 状态:已完成并验证

## 背景与目标

用户在 Claude Code 中安装并启用了三个语言服务器插件：`jdtls-lsp`（Java）、`typescript-lsp`（TypeScript/JavaScript）、`pyright-lsp`（Python）。逐个确认它们是否真正工作，若不工作则修复，使 `LSP` 工具（`documentSymbol` / `hover` 等操作）能对 `.java` / `.ts` / `.py` 文件正常返回结果。

本任务为本机工具链环境配置修复，非某个代码仓库内的功能开发，因此不涉及 `~/CLAUDE.md` 工作流中 Kanban 关联、`git worktree`、Gherkin/E2E、文档同步、PR 提交等环节；仅保留 spec.md / implementation.md 的记录方式（与 [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/) 一致）。

## 范围

- **In scope**：确认 `~/.claude/settings.json` 中三个插件均已在 `enabledPlugins` 启用；确认各插件依赖的外部可执行文件（`jdtls` / `typescript-language-server` / `pyright-langserver`）是否安装、版本是否兼容；用真实 `.java`/`.ts`/`.py` 文件通过 `LSP` 工具验证 `documentSymbol`、`hover` 可正常工作。
- **Out of scope**：插件本身的实现代码（这三个插件只是"注册 + README"，不含可执行文件，真正的语言服务器需要用户在系统层面单独安装，见下）；IDE/编辑器集成；除 Java/TypeScript/Python 外的其他语言服务器。

## 现状分析（Root Cause）

Claude Code 官方的 `*-lsp` 插件（`~/.claude/plugins/marketplaces/claude-plugins-official/plugins/<name>/`）本身只包含 `LICENSE` 和 `README.md`，不包含语言服务器可执行文件本身——它们只是告诉 Claude Code"这个文件类型有对应的语言服务器可用"，真正的服务器进程需要用户按各插件 README 的说明在系统 PATH 中单独安装。三个插件在 `~/.claude/settings.json` 的 `enabledPlugins` 中均为 `true`，插件层面没有问题；问题全部出在"底层依赖的可执行文件缺失或版本不兼容"。

### 1. jdtls-lsp（Java）

- 依赖：`jdtls`（Eclipse JDT.LS 命令行封装），要求 Java 17+。
- 现状：`java -version` 显示已装 OpenJDK 21（满足要求），但 `which jdtls` 找不到命令。
- 复现：`LSP documentSymbol` 报 `Command failed with ENOENT: jdtls` / `Executable not found in $PATH: "jdtls"`。
- 根因：`jdtls` 命令行工具从未安装，仅仅是 Java 环境就绪不代表 jdtls 本身就绪。

### 2. typescript-lsp（TypeScript/JavaScript）

- 依赖：`typescript-language-server`（社区 LSP 封装，内部通过 `tsserver`/`tsserver.js` 与 TypeScript 通信）+ `typescript`。
- 第一次复现：`which typescript-language-server` 找不到 → `LSP` 报 `ENOENT: typescript-language-server --stdio`。
- 执行 `npm install -g typescript-language-server typescript` 后二次复现：`LSP` 报 `Could not find a valid TypeScript installation`——不是 PATH 问题，而是版本不兼容：
  - npm `typescript@latest` 已经是 `7.0.2`，对应 TypeScript 官方近期发布的原生（Go 重写）编译器架构，该版本的 npm 包**不再打包旧版 `lib/tsserver.js`**。
  - `typescript-language-server@5.3.0`（npm 上最新版本）仍是基于旧版 `tsserver` JS API 构建的封装器，其自身构建时的 `devDependencies` 声明的是 `typescript: ^6.0.3`，尚未适配 TypeScript 7 的新架构。
  - 二者一新一旧，导致 `typescript-language-server` 启动时在全局 `typescript` 包里找不到 `tsserver.js`，初始化失败。
- 根因：全局安装的 `typescript` 版本（7.0.2）比 `typescript-language-server` 实际支持的版本（6.x 系列，仍带 `tsserver.js`）新了一个大版本，二者不兼容。

### 3. pyright-lsp（Python）

- 依赖：`pyright`（npm 包，内含 `pyright-langserver` 可执行文件）。
- 现状：`which pyright` / `which pyright-langserver` 均找不到。
- 复现：`LSP documentSymbol` 报 `Command failed with ENOENT: pyright-langserver --stdio`。
- 根因：`pyright` 从未安装。安装后未出现版本兼容问题（不同于 typescript-lsp）。

## 解决方案

统一通过 npm 全局安装／版本锁定的方式修复，不引入插件层面的改动：

1. **jdtls-lsp**：`brew install jdtls`（README 给出的 macOS 安装方式；会一并装上 `openjdk` 依赖，不影响已有的 OpenJDK 21）。
2. **typescript-lsp**：
   - `npm install -g typescript-language-server typescript` 先补齐 `typescript-language-server`；
   - 发现全局 `typescript` 被装成 7.0.2 导致不兼容后，改为 `npm install -g typescript@6.0.3` 锁定到仍带 `tsserver.js` 的最新 6.x 版本（与 `typescript-language-server` 自身构建依赖的版本一致）。
3. **pyright-lsp**：`npm install -g pyright`（README 给出三种安装方式之一；与 typescript-lsp 保持同一套 npm 全局工具链，避免混用 pip/pipx）。

## 验收标准

- [x] `~/.claude/settings.json` 的 `enabledPlugins` 中 `jdtls-lsp` / `typescript-lsp` / `pyright-lsp` 均为 `true`。
- [x] `which jdtls` / `which typescript-language-server` / `which pyright-langserver` 均能找到可执行文件。
- [x] 对测试用 `Hello.java` 执行 `LSP documentSymbol`，正确返回类/方法符号列表。
- [x] 对测试用 `Hello.java` 执行 `LSP hover`，正确返回方法签名。
- [x] 对测试用 `hello.ts` 执行 `LSP documentSymbol`，正确返回函数/常量符号列表。
- [x] 对测试用 `hello.ts` 执行 `LSP hover`，正确返回函数签名。
- [x] 对测试用 `hello.py` 执行 `LSP documentSymbol`，正确返回函数/变量符号列表（含函数内参数）。
- [x] 对测试用 `hello.py` 执行 `LSP hover`，正确返回带类型标注的函数签名。

## 风险与缓解

- **typescript 全局版本被后续 `npm update -g` 或其他工具重新升级到 7.x，导致 typescript-lsp 再次失效**：缓解——若未来 `typescript-language-server` 发布适配 TypeScript 7 新架构的版本，可同步升级两者；在此之前应避免无脑 `npm update -g typescript`。
- **`jdtls` 通过 Homebrew 安装，未来 `brew upgrade` 可能带来新版本行为变化**：影响面小，Eclipse JDT.LS 对 LSP 协议本身保持稳定，风险可接受。
- **这三个语言服务器进程依赖系统全局 PATH（`/opt/homebrew/bin`、nvm 管理的 node 全局 bin 目录）**：如果用户切换 Node 版本管理器（nvm）当前版本，`typescript-language-server` / `pyright-langserver` 所在的全局 bin 目录会变化，需要重新确认或重新安装。

## 参考

- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/jdtls-lsp/README.md`
- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/typescript-lsp/README.md`
- `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/pyright-lsp/README.md`
- `~/CLAUDE.md`「Overview」章节：优先安装/启用工具本身而非退化为替代方案。
- [git-clone-proxy](./2026-07-30-2027-git-clone-proxy/)（同类"单机环境配置修复"任务的记录格式参考）

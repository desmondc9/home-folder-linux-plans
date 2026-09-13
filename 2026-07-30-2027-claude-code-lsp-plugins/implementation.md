# Implementation: 三个 LSP 插件排查与修复

对应 spec.md 的全部范围（单阶段，无需拆分 phase；三个插件按 jdtls-lsp → typescript-lsp → pyright-lsp 顺序处理，彼此独立）。

## 依赖

无（本机工具链环境配置，不依赖其他任务）。

## 任务列表

### jdtls-lsp

- [x] 确认 `~/.claude/settings.json` 中 `jdtls-lsp@claude-plugins-official: true`。
- [x] 确认插件目录（marketplace/cache/data）只含 `LICENSE`/`README.md`，无内置可执行文件。
- [x] 诊断：`which jdtls` 未找到；`java -version` 已是 OpenJDK 21，满足 17+ 要求。
- [x] 复现：`LSP documentSymbol` 对测试 `Hello.java` 报 `ENOENT: jdtls`。
- [x] 修复：`brew install jdtls`（一并安装 openjdk 依赖）。
- [x] 验证：`which jdtls` 命中 `/opt/homebrew/bin/jdtls`。
- [x] 验证：`LSP documentSymbol` 对 `Hello.java` 正确返回 `Hello` 类及 `main`/`greet` 方法。
- [x] 验证：`LSP hover` 对 `greet()` 调用处正确返回 `String Hello.greet()`。
- [x] 清理测试文件 `Hello.java`。

### typescript-lsp

- [x] 确认 `~/.claude/settings.json` 中 `typescript-lsp@claude-plugins-official: true`。
- [x] 诊断：`which typescript-language-server` 未找到。
- [x] 复现（第一次）：`LSP documentSymbol` 对测试 `hello.ts` 报 `ENOENT: typescript-language-server --stdio`。
- [x] 修复（第一步）：`npm install -g typescript-language-server typescript`。
- [x] 复现（第二次）：安装后 `LSP documentSymbol` 报 `Could not find a valid TypeScript installation`。
- [x] 诊断：`tsc --version` 显示全局 `typescript` 为 `7.0.2`；`npm root -g` 下该包 `lib/` 目录内无 `tsserver.js`。
- [x] 诊断：`npm view typescript-language-server peerDependencies`/`devDependencies` 确认其自身构建依赖 `typescript ^6.0.3`；`npm pack typescript@6.0.3` 解包确认 6.0.3 仍带 `lib/tsserver.js`。
- [x] 修复（第二步）：`npm install -g typescript@6.0.3` 将全局 `typescript` 降级/锁定到 6.0.3。
- [x] 验证：`tsc --version` 显示 `6.0.3`；对应 `lib/` 目录下确认存在 `tsserver.js`。
- [x] 验证：`LSP documentSymbol` 对 `hello.ts` 正确返回 `greet` 函数与 `message` 常量。
- [x] 验证：`LSP hover` 对 `greet(...)` 调用处正确返回 `function greet(name: string): string`。
- [x] 清理测试文件 `hello.ts`。

### pyright-lsp

- [x] 确认 `~/.claude/settings.json` 中 `pyright-lsp@claude-plugins-official: true`。
- [x] 诊断：`which pyright` / `which pyright-langserver` 均未找到。
- [x] 复现：`LSP documentSymbol` 对测试 `hello.py` 报 `ENOENT: pyright-langserver --stdio`。
- [x] 修复：`npm install -g pyright`（与 typescript-lsp 保持同一套 npm 全局工具链，未使用 pip/pipx）。
- [x] 验证：`which pyright-langserver` 命中 nvm 管理的 node 全局 bin 目录；`pyright --version` 输出 `1.1.411`。
- [x] 验证：`LSP documentSymbol` 对 `hello.py` 正确返回 `greet` 函数（含参数 `name`）与 `message` 变量。
- [x] 验证：`LSP hover` 对 `greet(...)` 调用处正确返回 `(function) def greet(name: str) -> str`。
- [x] 清理测试文件 `hello.py`。

## 变更文件 / 环境变更

| 变更项 | 内容 |
|------|----------|
| Homebrew | 新增安装 `jdtls`（连带 `openjdk` 依赖），系统已有的 OpenJDK 21 未受影响 |
| npm 全局包 | 新增 `typescript-language-server@5.3.0`、`pyright@1.1.411`；`typescript` 从默认拉取的 `7.0.2` 改为锁定安装 `6.0.3` |
| `~/.claude/settings.json` | 无变更（三个插件此前已在 `enabledPlugins` 中启用，本任务未修改插件启用状态） |

未涉及任何代码仓库文件、API、数据库变更。

## 验证方式

- `which jdtls` / `which typescript-language-server` / `which pyright-langserver`：确认三个可执行文件均在 PATH 中。
- 对 `/private/tmp/.../scratchpad/` 下临时创建的 `Hello.java`、`hello.ts`、`hello.py` 分别执行 `LSP` 工具的 `documentSymbol` 与 `hover` 操作，确认均返回正确结果而非报错。
- 测试文件均为临时文件，验证完成后已删除，不留存于仓库或用户目录中。

## 备注

- 本任务未创建 `git worktree` / 分支 / PR，因为改动对象是本机全局工具链（Homebrew 包、npm 全局包），不属于任何代码仓库内的功能开发，`~/CLAUDE.md` 工作流中 Kanban 关联、Gherkin/E2E、文档同步等步骤不适用。
- **教训（可迁移经验）**：Claude Code 官方 `*-lsp` 插件本身不包含语言服务器可执行文件，只是"声明支持"；真正生效前必须按插件 README 在系统层面单独安装对应工具，且要注意**版本兼容性**而非只看"命令是否存在"——`typescript-lsp` 一例中，命令装上了但因为拉到了不兼容的最新大版本（TypeScript 7 原生编译器 vs. 仍基于旧 tsserver API 的 `typescript-language-server`）依然不工作，必须验证到实际 LSP 请求（如 `documentSymbol`/`hover`）成功返回，才能确认"真的工作"。
- 若未来迁移到新机器 / 重装环境，只需按本文件"任务列表"顺序重新执行对应的 `brew install` / `npm install -g` 命令，并留意 `typescript` 版本需锁定在 6.x（而非直接装 latest）。

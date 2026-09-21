# LazyVim Java/Python/Rust/TypeScript/JavaScript LSP 与 DAP 实测审计

> 日期:2026-09-21。目标:不只检查配置和 binary,而是在最小真实项目中完成 LSP 协议往返与 DAP 断点命中,并在 HMS Spring Boot 真实项目中验证 Java 项目级边界。

## 结论

- Python、Rust、TypeScript、JavaScript 的 LSP 与 DAP 均有效。
- Java 最小 Maven 项目的 jdtls、main-class discovery、java-debug-adapter launch/attach 链路有效。
- HMS Spring Boot 项目中 jdtls 的普通 LSP 功能有效,java-debug-adapter remote attach 有效;但存在两个已复现缺口:
  1. `prepareRename` 报 `Renaming this element is not supported.`(仓库备份里的 `java-rename.lua` 正是该 workaround,当前未恢复)。
  2. 自动 main-class DAP 配置不发布:项目 6 个 `main` 中至少两个 utility class 无法 resolve Java executable,触发 nvim-jdtls pending counter 不归零的边界,导致可用的 Spring Boot main 配置也不进入 `dap.configurations.java`;当前只剩 remote attach。
- 未安装 Spring 专用 language server / dashboard。它不影响普通 Java LSP 或 DAP,但缺少 Spring configuration metadata、bean 导航/Boot dashboard 等 Spring 专属体验。

## 环境与已安装链路

| 语言 | LSP | DAP | 相关运行时/工具 |
|---|---|---|---|
| Java | jdtls + nvim-jdtls | nvim-dap + java-debug-adapter(JAR bundle) | OpenJDK 21.0.2;java-test |
| Python | pyright + ruff | nvim-dap-python + debugpy | Python 3.14.4 |
| Rust | rustaceanvim + rust-analyzer | codelldb | rustc/cargo 1.98.1;rustfmt 1.9.0 |
| TypeScript/JavaScript | vtsls | pwa-node(js-debug-adapter) | Node 24.21.0;npm 11.19.0 |

通用 DAP UI:nvim-dap-ui + nvim-dap-virtual-text;mason-nvim-dap 负责 adapter 接线。

## 实测矩阵

在 `/tmp/opencode/nvim-probe/` 创建最小 Python、Cargo、TypeScript/JavaScript、Maven 项目;每种语言均以 headless Neovim 打开真实源文件。

LSP 通过标准 `textDocument/documentSymbol` 请求验证,不是仅检查进程:

| 语言 | attach clients | 协议请求 |
|---|---|---|
| Python | pyright,ruff | pyright 返回 1 symbol ✅ |
| Rust | rust-analyzer | 返回 2 symbols ✅ |
| TypeScript | vtsls | 返回 1 symbol ✅ |
| JavaScript | vtsls | 返回 1 symbol ✅ |
| Java | jdtls(+copilot) | 返回 2 symbols,jdtls 到 ServiceReady ✅ |

DAP 以真实程序运行 + 指定源代码行断点 + 等待 `event_stopped` 验证:

| 语言 | adapter | initialized | 断点结果 |
|---|---|---|---|
| Python | debugpy | true | `reason=breakpoint` ✅ |
| Rust | codelldb | true | `reason=breakpoint` ✅ |
| TypeScript | pwa-node | true | `reason=breakpoint` ✅ |
| JavaScript | pwa-node | true | `reason=breakpoint` ✅ |
| Java | java-debug-adapter,attach 到 suspend=y JDWP JVM | true | stopped event ✅ |

Python headless probe 强制 terminate 后 UI 曾打印 `Error retrieving stack traces: Server disconnected unexpectedly`,但断点已先命中且进程 exit code=0;这是测试清理竞态,不是 adapter 启动/断点故障。Python 3.14.4 下 debugpy 本次可用。

## HMS Spring Boot 真实项目结果

目标:`~/Repos/ups-hms-all-in-one/backend/src/main/java/com/ups/upshmsbackend/UpsHmsBackendApplication.java`。

- jdtls attach root 正确指向 backend 根目录;项目导入达到 Ready/ServiceReady。
- documentSymbol 成功:普通 LSP 有效。
- `textDocument/prepareRename` 在 application class 上实测失败:`Renaming this element is not supported.`。
- `setup_dap_main_class_configs()` 调用成功,但 120 秒后仍只有静态 `Debug (Attach) - Remote`;没有 `Launch ... UpsHmsBackendApplication`。
- jdtls 输出无法为 `VirtualThreadPerformanceTest`、`BarCodeCalculator` 等 utility main resolve Java executable。
- nvim-jdtls `lua/jdtls/dap.lua` 的 discovery 用 `remaining=#mainclasses`;只有 `with_java_executable(..., callback)` 的 callback 内才递减。`lua/jdtls/util.lua` 在 java executable 为 nil 时只 print、不调用 callback,所以任一失败候选都会阻止最终 configurations callback。HMS 恰有 6 个 `static void main`,触发该边界。

## 当前缺口与优先级

### P1:恢复 HMS rename workaround

仓库备份:`~/Repos/desmondc9-home-folder/.config/nvim/lua/plugins/java-rename.lua`。此前用户选择只恢复 copy-path,因此当前未恢复。实测证明该 workaround 仍有必要。恢复前应把它复制到 `~/.config/nvim/lua/plugins/` 并复跑 prepareRename。

### P1:为 HMS Spring Boot main 添加显式 DAP launch 或修复 discovery

可选方向:

1. 项目/用户配置中显式添加 `dap.configurations.java` 的 Spring Boot main launch(固定 `mainClass=com.ups.upshmsbackend.UpsHmsBackendApplication`,JAVA_HOME Java 21,classpath 由 jdtls resolve);或
2. 修补/上报 nvim-jdtls discovery:resolve Java executable 失败时也递减 pending counter,保留其他成功候选;或
3. 继续用当前已验证的 remote attach(`mvn spring-boot:run` 带 JDWP 参数 + `Debug (Attach) - Remote`)。

### P2(可选):Spring 专属语言体验

当前没有 Spring Boot language server / Boot dashboard。若用户只需要 Java 编码 + Spring Boot 断点,现状加上上述 launch 修复已够;若需要 `application.yml` 属性 metadata、bean navigation、Boot dashboard,再专门评估 Spring tools 插件,不要把它误判为 Java LSP/DAP 的必要条件。

## 未发现的缺口

- Python:pyright + ruff 双 LSP、debugpy DAP、neotest-python 均已接线;Python 3.14 本次断点通过。
- Rust:rust-analyzer、rustfmt、rustaceanvim、codelldb 都存在且断点通过。
- TypeScript/JavaScript:vtsls 同时覆盖 `.ts`/`.js`;js-debug-adapter 的 pwa-node 两种文件均断点通过。
- Java:minimal Maven main discovery 可生成 `Launch nvim-probe: com.example.App`;java-test 和 java-debug-adapter Mason bundles 均存在。

## 验证边界

- 本次没有启动完整 HMS Spring Boot 应用(它依赖真实/本地 GCP、数据库等服务);验证到 jdtls 项目导入、协议请求、main discovery 和独立 JDWP attach。
- 没有修改 Neovim 配置;所有 probe 文件都位于 `/tmp/opencode/nvim-probe/`。

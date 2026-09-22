# nvim Java test 发现失败排查之旅 — "No suitable test method found"

- **日期**: 2026-09-22(调查始于 17:00,约 2.5 小时)
- **场景**: `ups-hms-all-in-one/.worktrees/2026-09-21-1726-lazyvim-java-lsp/backend` + LazyVim(`extras.lang.java` + `extras.test.core`)
- **症状**: `<leader>tr` / `<leader>tt` 跑测试报 `No suitable test method found` / `No test class found`
- **性质**: 调查留档(无 repo PR;附带两处配置修改,见 §5)

## TL;DR

1. **根因**: pom 的 `maven-compiler-plugin` 配了 `<compilerArgs><arg>--enable-preview</arg></compilerArgs>`。m2e 把它映射为 JDT 工程选项 `enablePreviewFeatures=enabled` 后,java-test 插件(`JUnit5TestFinder.isTest` → `ASTParser.setProject + createBindings`)的 binding 解析静默降级 → 所有类被判"非测试类" → LSP 命令 `vscode.java.test.findTestTypesAndMethods` 返回 `[]` → nvim-jdtls 找不到 method lens。而代码库 **0 处 preview 特性使用**,该 flag 是遗留配置。
2. **修复**: 从 pom 删除该 compilerArgs 块(已应用并端到端验证;surefire 的运行时 flag 保留)。
3. **上游**: [microsoft/vscode-java-test#1692](https://github.com/microsoft/vscode-java-test/issues/1692)(2024-05 开、仍 open)。以 desmondc9 账号发了 minimal repro 评论;后续实测 **jdt.ls 1.61.0(2026-09-03)+ Test Runner 0.46.0 之下 Maven 路径依然坏**(维护者验证的是 Eclipse 工程格式,不覆盖 m2e 映射路径),已把该 Update 编辑进原评论。
4. **顺带修复**: jdtls workspace 目录按 root 路径 hash 隔离(主仓与 9 个 worktree 的 `backend` 原本共享同一 Eclipse workspace)。

## 排查历程(假设 → 实验 → 结论)

| # | 假设 | 实验 | 结论 |
|---|---|---|---|
| 1 | java-test bundle 没加载 | 日志分析 | ❌ 排除——命令已注册;asm 9.10.1 OSGi 冲突是噪音(jdt.ls 自带同版本) |
| 2 | jdtls workspace 损坏(主仓/worktree 同名共享) | 擦除 workspace 冷导入重测 | ❌ **证伪**——仍空;但这是真隐患,后顺手修了(§5.1) |
| 3 | JUnit 依赖/类路径问题 | `resolvePath`/`isTestFile`/`getClasspaths(scope=test)` 探针 | ❌ 排除——测试包 testLevel=4、junit 5.11.4 在 classpath、文件 0 错误 |
| 4 | binding/hover 坏了 | hover `@Test` → 完整 javadoc | ❌ 排除——LSP reconcile 管线正常 |
| 5 | 工程差异(spring/lombok/mapstruct/system-jar/preview) | **二分法最小复现**:mini-a(spring 组合)✅ / mini-b(preview+lombok+mapstruct+system jar)❌ → mini-c(显式 compiler 配置)✅ / **mini-d(唯一变量=preview)❌** / mini-e(三库)✅ | ✅ **单变量锁定 `--enable-preview`** |
| 6 | 真实工程验证 | backend pom 临时删 preview → 探针返回 testLevel=6 的方法 lens → 还原 pom | ✅ 端到端确认 |
| 7 | 升级到最新可修复 | jdt.ls 1.60.0→**1.61.0**(手动覆盖 mason)+ marketplace 0.46.0 → mini-d 仍 ❌、mini-c 对照 ✅ | "已修复"只对 Eclipse 工程格式生效,**Maven/m2e 路径未修** |

关键中间证据(排除过程的"钉子"):

- headless nvim 复现:attach 正常、root_dir 正确、`findTestTypesAndMethods` 三次探测(+5/+15/+30s)恒为 `[]`(非超时、非报错)
- 反编译 `com.microsoft.java.test.plugin-0.43.1.jar` + jdt.ls 的 `org.eclipse.jdt.junit.core`:完整调用链 `TestKindProvider → JUnit5TestSearcher.isTestClass → JUnit5TestFinder.isTest → ASTParser.createBindings → @Testable 元注解链`
- 原 issue #1692 里的 ECJ 报错补上了最后一环:`Preview features enabled at an invalid source release level 21, preview can be enabled only at source level 22 (code 2098258)`——ECJ 只认最高 source level 的 preview,该路径下错误不冒泡、binding 静默失效

## 为什么症状如此迷惑(值得记住的架构点)

jdt.ls 内有**两套独立编译入口**,preview 只毒害其中一套:

| 路径 | 用途 | preview 下表现 |
|---|---|---|
| reconcile 管线(working-copy 编译器) | 诊断、hover、补全 | ✅ 正常 → 编辑器看起来"一切健康" |
| 插件自起的 `ASTParser.setProject + createBindings` | java-test 的测试类判定 | ❌ binding 静默失败 → 返回空数组 |

## 附带发现与修复

### 1. jdtls workspace 同名冲突(隐患,非本次根因)

LazyVim java extra 用 `vim.fs.basename(root_dir)` 作项目名 → 主仓和每个 worktree 的 `backend` 共享 `~/.cache/nvim/jdtls/backend/`。修复:`~/.config/nvim/lua/plugins/java.lua` 覆盖 `project_name` 追加 `sha256(root_dir)` 前 8 位(注意正确的 seam 是 `project_name` 而非 `jdtls_workspace_dir`——后者拿不到 root 路径;config 和 workspace 两个目录因此同时隔离)。

### 2. `<leader>td` "no tests found" 是按键路由问题

neotest(全局映射)与 jdtls(java buffer 内覆盖 `tt`/`tr`/`tT`)并存;`td`(Debug Nearest)只属于 neotest,而 Java 没有 neotest adapter → 永远报 no tests found。**Java 的 debug = 打断点 + `tr`/`tt`**(jdtls 测试运行天生是 DAP session)。

### 3. 观察到的 mason 行为

- LazyVim glob `share/java-test/*.jar` 会把 junit runtime jar 也当 OSGi bundle 装进 jdt.ls(asm 冲突噪音即来源于此)
- 删除 mason 包后,**打开着的 nvim 会话**里 `ensure_installed` 会自动重装 pin 的版本(排查中观察到的混合状态即此)

## 上游互动记录

- 2026-09-22 18:31 以 desmondc9 发表 minimal repro 评论:[#1692 comment-5774951768](https://github.com/microsoft/vscode-java-test/issues/1692#issuecomment-5774951768)
- 维护者侧已有结论(2026-06-29,wenytang-ms):需 redhat.java ≥1.55.0 + Test Runner ≥0.46.0;但其验证场景是 Eclipse 工程格式
- 2026-09-22 18:5x 把"最新组合下 Maven 路径仍坏 + 对照通过"的 Update **编辑进原评论**(含 marketplace 两个构建的 plugin jar 均仍为 0.43.1 的事实)

## 环境最终状态

| 项 | 状态 |
|---|---|
| `backend/pom.xml` | compilerArgs(--enable-preview)已删,`git diff` 3 行,待随工作分支提交 |
| nvim `lua/plugins/java.lua` | 新增,workspace 按 hash 隔离 |
| mason jdtls | 手动覆盖为 1.61.0(receipt 元数据仍旧;mason 若重装会回 1.60.0,无妨——两版都有此 bug) |
| mason java-test | 曾短暂混合态,重启 nvim 后 mason 自动重装归位 |
| jdtls 缓存 | `~/.cache/nvim/jdtls/` 全部按新 hash 命名重建 |

## 复用资产(本目录)

- `repro/mini-d/` — 最小复现(pom + 1 个 JUnit5 测试类,唯一变量 `--enable-preview`);删掉 compilerArgs 即对照组 mini-c(`repro/mini-c/pom.xml`)
- `scripts/` — headless 探针:`jdtls_probe.lua`(executeCommand 全套探针+重试)、`jdtls_repro.lua`(lens 原始 dump+光标匹配模拟)、`jdtls_verify.lua`(长轮询)、`jdtls_hover.lua`(binding 探测)。用法:`PROBE_FILE=<java文件> nvim --headless -u ~/.config/nvim/init.lua "+luafile <脚本>"`

## Follow-ups

- [ ] pom 修改随 `2026-09-21-1726-lazyvim-java-lsp` 分支正常走 PR;CI 无影响(代码 0 处 preview 使用)
- [ ] 关注 #1692 后续(已订阅);若维护者需要,可提供 m2e 映射层面的进一步 dump
- [ ] 等 mason registry 把 jdtls pin 到 ≥1.61 后,`:Mason` 更新即与手动覆盖对齐
- [ ] (可选)等上游修复后,评估是否恢复 `--enable-preview`(目前无任何功能损失)

## 方法论小结

1. **多组件系统先在边界抓数据**:headless nvim + LSP executeCommand 探针,把"服务器到底返回了什么"钉死,再决定往哪层挖
2. **二分法最小复现**胜过一切推理:mini-a/b/c/d/e 五个 10 行 pom 的对照实验,把 5 个嫌疑收敛到 1 个
3. **对照实验要有对照组且同时跑**:mini-c ✅ / mini-d ❌ 的同组合对照,让"升级无效"的结论无可辩驳
4. **反编译是最后的显微镜**:插件 jar + jdt.ls bundle 的字节码读出了完整判定链,定位到唯一可疑点
5. **证伪也是产出**:"workspace 损坏"假设被证伪的过程顺带暴露了真隐患(同名冲突),顺手修复

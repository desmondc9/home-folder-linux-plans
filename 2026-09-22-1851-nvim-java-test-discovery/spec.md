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

- [x] pom 修改以正式 PR 落库:backend **PR 18213**(drop preview,`f422af25d4`)+ umbrella **PR #18222**(pin 提升)均已合并;本地收尾见下方 2026-09-23 执行记录
- [ ] 关注 #1692 后续(已订阅);若维护者需要,可提供 m2e 映射层面的进一步 dump
- [ ] 等 mason registry 把 jdtls pin 到 ≥1.61 后,`:Mason` 更新即与手动覆盖对齐
- [ ] (可选)等上游修复后,评估是否恢复 `--enable-preview`(目前无任何功能损失)
- [ ] (可选)`origin/feature/pin-backend-drop-preview-flags` 远程分支仍留在 ADO,如需清理在 PR 页面删除
- [ ] (建议)主仓 `.vscode/settings.json` 的 `**/.worktrees/**` 排除目前是本地未提交修改,值得走一个 umbrella PR 让全组受益

## 2026-09-23 追认:VSCode 侧同病同源(inline Run/Debug CodeLens 消失)

用户次日报告 VSCode(Windows 主机 + WSL remote)打开同一项目时,test 方法上方没有 Run/Debug CodeLens。排查确认**同一条根因链,无需新假设**:

1. **机制同一**:VSCode 的测试 CodeLens 由 Test Runner for Java(`vscjava.vscode-java-test` WSL 侧 0.46.0)提供,调用的是同一个 jdt.ls 内嵌插件 `com.microsoft.java.test.plugin` 的 `vscode.java.test.findTestTypesAndMethods`——与 nvim-jdtls 完全同一条服务端路径。redhat.java 1.56.0 + TR 0.46.0 满足"≥1.55/0.46 仍坏"的已知条件。
2. **实锤签名**:worktree 窗口(`workspaceStorage/57d0b057…/redhat.java/jdt_ws/.metadata/.log`)里存在 `Preview features enabled at an invalid source release level 21, preview can be enabled only at source level 26; code: 2098258`,resource 指向 `.worktrees/2026-09-21-1726-lazyvim-java-lsp/backend/src/main/java/…`——即 #1692 的 ECJ 静默降级在本机 VSCode 的直接证据。
3. **为什么修复后仍坏(两层)**:
   - 修复已正式落库:backend 子模块 PR 18213(drop preview,`f422af25d4`)+ umbrella PR #18222(pin → `2cb92732b1`)均已合并;但**本地主仓落后**(umbrella main 落后 origin/main 34 commits,backend 检出停留在修复前的 `9d02357cfd` 本地 develop)→ 主仓窗口的 pom 仍带 `--enable-preview`(L736)。
   - worktree 窗口的 jdt_ws 工程状态是 09-21 20:08/20:28(修复前)导入的,pom 事后改了,但该窗口的 Java LS 再没启动过(client.log 停在 09-21)→ 陈旧映射未刷新。
4. **修复**(主仓):`git pull --ff-only origin main && git submodule update backend` + VSCode "Java: Clean Java Language Server Workspace"(清两个陈旧 jdt_ws),重开窗口等 import 完成。
5. **状态更新**:worktree `2026-09-21-1726-lazyvim-java-lsp/backend` 里未提交的 ` M pom.xml` 手动修复自此冗余(上游已正式修复);Follow-up #1("pom 修改随分支走 PR")以 PR 18213 + #18222 的形式完成,可勾销。

### 最终确认(2026-09-23 09:49-10:00,VSCode 自愈复现)

用户今早在同一 worktree 窗口重开 backend,09:49 jdt.ls 起了全新会话(扩展 redhat.java 1.56.0 实际捆绑 **jdt.ls 1.61.0-SNAPSHOT 2026-09-02 构建**)——该会话以修复后的 pom 重新导入,**全程 0 条新 preview 错误**,test discovery 恢复 → test 方法 gutter 出现绿色箭头(Run/右键 Debug)。诊断闭环:根因唯一且修复有效。

时间线澄清:昨天用户看的是 worktree 窗口没错,但 (a) 该工作区 jdt_ws 在 9-22 全天无新会话(Java LS 停在 9-21 20:28 的中毒状态);(b) pom 修复 9-22 ~19:00 才落地。今早重启窗口 → 新会话吃到干净 pom → 恢复。**"重启/重开窗口"本身是修复生效的必要一步**。

## 2026-09-23 收尾执行记录(含计划修正)

### 关键源码结论:exclusions 匹配语义(决定设置放置)

读 jdt.ls 上游源码(`BasicFileDetector.java`,`MavenProjectImporter.applies()` 调用):`java.import.exclusions` 的 glob 由 `FileSystems.getPathMatcher("glob:"+pattern)` 对 **walkFileTree 遍历到的目录绝对路径**做匹配,命中即 `SKIP_SUBTREE`。推论:

- **User 全局放 `**/.worktrees/**` 会炸掉"直接打开 worktree backend"的窗口**——工作区根自身路径就含 `.worktrees/`,整棵树被跳过 → Maven 工程不导入(退化为 invisible project,无依赖)。
- 唯一安全位置:**umbrella 的 `.vscode/settings.json`(工作区级)**——只有以主仓为根的窗口读它,恰好是唯一需要排除 `.worktrees` 的场景。注意 settings.json 设置该键会**整体覆盖默认值**,必须带上 4 条默认再追加。

### 执行清单(实际)

| 项 | 结果 |
|---|---|
| 主仓 backend pom | ✅ 外科手术:删 compilerArgs 3 行(与 worktree 同型);surefire 运行时 flag 保留 |
| worktree pom 手动修复 | ✅ **保留不丢弃(计划修正)**:该 worktree 分支 pin 的 backend `dd604f51a5` 仍是修复前 commit,丢弃本地编辑会把 `--enable-preview` 带回来,毒化正在使用的 VSCode 窗口。若要真正干净,应把 `feature/lazyvim-java-lsp` rebase 到 main(其 pin 已含修复)后再丢 |
| umbrella main 同步 | ⛔ **跳过(计划修正)**:主仓实际有 33 处本地修改(deploy/seed 脚本、5 个子模块指针、load-test 计划等),其中 5 处与 incoming 重叠(`backend`、`web`、`endpoints`、`release.sh`、`load-test-plan.md`);stash+pull+pop 需在在途工作上做冲突手术,而 pull 的关键 payload(backend pin)因 backend 内有已暂存的用户工作(`BarCodeCalculator.java` 重构)本就无法应用。收益/风险不成立 |
| 子模块更新 | ⛔ 全部跳过(同上,各子模块均有本地修改,是用户活跃工作区) |
| 已合并 worktree 清理 | ✅ `2026-09-22-2204-pin-backend-drop-preview` remove(含子模块需 `--force --force`;移除前确认 umbrella+backend 均无未提交内容)+ 本地分支 `feature/pin-backend-drop-preview-flags` 删除(真 merge,-d 成功);远程分支留 ADO |
| `.vscode/settings.json` | ✅ 追加 `java.import.exclusions`(4 默认 + `**/.worktrees/**`);该文件被 git 跟踪 → 成为本地未提交修改,建议后续走 PR 提交 |
| 主仓窗口陈旧 jdt_ws | ✅ `workspaceStorage/060f6a69…/redhat.java/jdt_ws` 删除(日志与 ss_ws 保留;删前确认无 java 进程;注意 ps 自匹配误报要用 `awk '/\/bin\/java/ && /060f6a69/'` 这种双条件) |

### 用户工作区状态(未动一字节)

主仓 backend 的暂存 `BarCodeCalculator.java` 重构、`entrypoint.sh` 权限位、未跟踪 `systemfile/`、umbrella 的 33 处本地修改、其余 worktree——全部保持原样。

## 方法论小结

1. **多组件系统先在边界抓数据**:headless nvim + LSP executeCommand 探针,把"服务器到底返回了什么"钉死,再决定往哪层挖
2. **二分法最小复现**胜过一切推理:mini-a/b/c/d/e 五个 10 行 pom 的对照实验,把 5 个嫌疑收敛到 1 个
3. **对照实验要有对照组且同时跑**:mini-c ✅ / mini-d ❌ 的同组合对照,让"升级无效"的结论无可辩驳
4. **反编译是最后的显微镜**:插件 jar + jdt.ls bundle 的字节码读出了完整判定链,定位到唯一可疑点
5. **证伪也是产出**:"workspace 损坏"假设被证伪的过程顺带暴露了真隐患(同名冲突),顺手修复

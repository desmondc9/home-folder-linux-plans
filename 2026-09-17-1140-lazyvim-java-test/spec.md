# LazyVim Java "run test" 修复(jdtls.dap → neotest-java)

- 日期:2026-09-17
- 症状:backend(ups-hms-all-in-one/backend)任意测试方法内按 `<leader>t r` → `No test class found`,每次必现
- 项目:/home/desmond/Repos/ups-hms-all-in-one/backend(Maven,Java 21,Spring Boot 3.4.3,JDK 由 sdkman 管理)

## 结论(TL;DR)

`<leader>t r` 根本不是 neotest —— 是 LazyVim **lang.java extra** 在 LspAttach 时注册的
`jdtls.dap.test_nearest_method()`(java.lua L249-268),其依赖的 vscode-java-test 服务端
`vscode.java.test.findTestTypesAndMethods` 在本机版本组合下**对该项目恒返回空**。
网上"neotest-java 没配好"的说法方向对了但对象错了:本机压根没装 neotest(test.core extra 未启用)。

修复 = 启用 `test.core` extra + neotest-java adapter + 关掉 java extra 的测试键位劫持。
已在本仓库真实测试文件上端到端验证 `passed=1`。

## 根因链(逐层验证过,非推测)

版本矩阵(修复前):jdt.ls **1.60.0** + java-test **0.43.1**(mason) + java-debug-adapter 0.53.2 + nvim-jdtls 6e9d953 + LazyVim(java+dap extra,无 test extra)

1. **键位来源**:`<leader>t` 组来自 lang.java extra(条件:mason 装了 java-test + java-debug-adapter;
   2026-09-12 的 dap-setup 调查装齐了两者,键位从此生效),不是 neotest。
   test.core extra 未启用 → 无 neotest 插件。
2. **discovery 空**(headless 真机复现,`/tmp/opencode/jdtls-repro/`):
   - `vscode.java.test.findTestTypesAndMethods(file-uri)` → `[]`(repro2/4a/5/6/7)
   - 同一 server 项目级搜索正常:`findTestPackagesAndTypes("=ups-hms-backend")` 返回 **188** 个测试类,
     `get.testpath` 正确识别 src/test/java(isStrict=true)→ 测试根、TestKind、SearchEngine 全通
   - **坏的是文件/类级 AST 路径**:`parseToAst(unit, fromCache=true)` → `CoreASTProvider.getAST`
     /`ASTNodeSearchUtil`/binding 链条(0.43.1 的 TestSearchUtils L263、L336),backend 项目上返回空,
     最小 Maven 项目上正常 —— 未最终定位到 JDT 内部哪一行(收益递减,停止)
   - 网上对应 issue:mfussenegger/nvim-jdtls **#844**(本人 2026-09-09 所提,open;当时分析的是 0.46 的
     TestKindProvider 缓存竞争;本次实测 0.43.1 的 `getTestKindsFromCache` miss 时会现算,所以 0.43.1
     是另一层——文件级 AST 路径——同样坏)
3. **m2e classpathProvider 缺失**(次要,jdtls 工作区 .log):
   `vscode.java.resolveClasspath` → `Referenced classpath provider does not exist:
   org.eclipse.m2e.launchconfig.classpathProvider` —— jdt.ls 1.60 的 plugins 不带
   `org.eclipse.m2e.launching`。触发者是 LazyVim `dap_main={}` → `setup_dap_main_class_configs`。
   纯日志噪音;debug plugin jar 0.53.2 已是最新(扩展 0.59.0 内嵌的就是它),无版本可升。上游现状。
4. **mason java-test 包 asm 重复 bundle**(mason-org/mason-registry **#16867**,本人所提,open):
   0.43.1 与 0.46 同样带 3 个 `org.objectweb.asm*.jar`,与 jdt.ls 自带同版本冲突,OSGi install 失败
   (实测 jdt.ls 1.60 下非致命,插件仍激活,但日志噪音)。
5. **历史档案**(~/plans,注意目录无点!`~/.plans` 不存在):
   - 2026-09-12-1315-lazyvim-dap-setup:装了 java-debug-adapter+java-test → 触发问题键位
   - 2026-09-05-1043-jdtls-preparerename-fix / 2026-09-05-0040-lazyvim-learning-workspace:无测试相关结论
   - GitHub #844 + mason#16867(2026-09-09)即本人前次调查,当时降级 java-test 0.46→0.43.1 未解决

## 修复方案(已实施并验证)

| 变更 | 文件 | 说明 |
|---|---|---|
| 启用 test.core extra | `~/.config/nvim/lazyvim.json` | neotest + `<leader>tr`=Run Nearest / `tt`=Run File / `td`=Debug Nearest 等 |
| java 测试接入 | `~/.config/nvim/lua/plugins/java-neotest.lua`(新) | ① nvim-jdtls `test=false` + `dap_main=false`(去键位劫持/去 asm bundle 注入/去 main 扫描噪音)② neotest-java adapter ③ 包装 `is_test_file` 与 cwd 解耦 ④ 关掉 golang/python adapter(防 $HOME 全盘扫描) |
| junit console jar | `~/.local/share/nvim/neotest-java/` | 手动下载 1.10.1 + 6.0.3(sha256 与 default_config 一致;`:NeotestJava setup` 交互式无法 headless) |
| mason 升级 | java-debug-adapter 扩展 0.53.2→0.59.0 | debug plugin jar 版本不变(0.53.2 即最新) |

neotest-java 机制(为何能绕开全部坏点):treesitter 发现(不碰 vscode-java-test)+
`java/buildWorkspace`/`java.project.getClasspaths`(jdt.ls 自身命令,实测 376 条含 test-classes)
+ junit-platform-console-standalone 运行 + XML 报告回读。

### 包装 is_test_file 的原因

neotest-java 的 `is_test_file` 用 **adapter 创建时的 cwd** 向上找 pom(root_finder);
从 umbrella 根(无 pom.xml)启动 nvim 时 root=nil → 所有 java 文件被拒 → run 静默无操作。
包装后纯文件路径判断(Tests?/IT/Spec 结尾 + 路径不含 /main/),与启动目录无关。

## 验证(headless,真机)

1. cwd=umbrella 根 + 包装后:`is_test_file=true`,run nearest → `passed=1 failed=0`(13:13:28)
2. cwd=backend:`passed=1 failed=0`(13:11:01)
3. 运行命令核对:`java -jar console-standalone-6.0.3.jar … --classpath=<376 条> --select-method=
   com.ups.upshmsbackend.abandon.vo.AbnRowVoJsonNameTest#thePackageRowSerialises…`(neotest-java.log)
4. 配置冒烟:`CONFIG_OK`

## 已知边界

- **首次/克隆后需 `./mvnw test-compile`**:neotest-java 的 LspCompiler 是 fire-and-forget,
  不等编译;headless 短生命周期下 target/ 无产物则 tests=0 → failed。交互式长驻 nvim 下
  jdt.ls autobuild 会增量维护 target/,但首次仍建议手动 compile。
- 集成测试(@Tag("IntegrationTest"),Testcontainers)仍走 `./mvnw test`;console 跑的是纯单测。
- jdt.ls 文件级 discovery 的上游 bug(#844)未修,nvim-jdtls 原生 test runner 不可用直到上游修复。

## 参考

- mfussenegger/nvim-jdtls#844、mason-org/mason-registry#16867
- vscode-java-test 0.43.1 源码:TestSearchUtils.java / TestKindProvider.java / ProjectTestUtils.java(tag 0.43.1)
- 复现脚本与日志:/tmp/opencode/jdtls-repro/(临时,不归档)

---

## 第二轮调查(2026-09-17 下午):「第一次 run test 成功、第二次(设断点后)失败」

症状与断点无关(<leader>tr 普通运行根本不经过断点)。真正机制(headless 全程实测):

### jdt.ls 1.60 + m2e 2.7.700 的三宗罪

1. **import/update 会清空 target/*.class 且不重建**:jdtls 会话 attach 后 ~10-60s,m2e 的
   import/update 流程把 target/classes 与 target/test-classes 的 .class 全删(资源文件保留),
   之后没有任何重建(观察 7 分钟仍为 0)。fresh 工作区、脏退出的 warm 工作区、以及
   「maven 写过产物而 jdt.ls 构建状态不认」的会话都会触发;正常收敛的 warm 会话不触发
   (但 maven 一旦再写产物,下个会话又会触发)。
2. **保存源码不落盘**:converged warm 会话里 didChange+didSave 后 90s,.class mtime 不变
   —— jdt.ls 的编译输出在本机从不写盘。
3. **buildWorkspace 挂死**:`java/buildWorkspace`(自定义 LSP 方法,force 与否均同)请求
   永不返回;jstack 显示服务端线程全部空闲,请求失踪。

用户时间线还原:14:41:09 run1 的 junit 在清空前跑完(成功)→ 14:41:36 run1 的
buildWorkspace 触发状态对账 → 清空 8228 个 .class → run2/3/4 落在空窗口 →
javap "class not found" → junit tests=0 → `--fail-if-no-tests` → failed。

### 修复(已实施 + 两轮 E2E 验证)

neotest-java 默认依赖 jdt.ls 的 LspCompiler(fire-and-forget buildWorkspace)——在本机
完全不可依赖。改为 **Maven 作为唯一编译者**(~/.config/nvim/lua/plugins/java-neotest.lua):

- `build_spec` 前检查:测试类 .class 存在且不旧于源文件,且 src 树无比 maven 编译清单
  (target/maven-status/.../inputFiles.lst)新的 .java → 新鲜直接跑;
- 不新鲜 → 同步 `./mvnw test-compile -q`(nio future 等待,不阻塞事件循环);
- **竞态兜底**:spec 构建后再核一次 .class(防 import 清空落在检查之后)→ 被清则
  重编 + 重建 spec(清空每会话最多一次,重试安全)。

验证:①最坏场景(全新 jdtls 工作区 + import 清空 + 空产物)→ 自动重编 → **passed=1**
(4m45s);②warm + 产物新鲜 → **passed=1(约 10s,零 maven 开销)**。

### 使用注意

- 首次跑测试 / jdt.ls 刚 import 清空产物后跑测试:自动 maven 重编,约 1-5 分钟,有通知提示;
- 日常"改代码→跑测试":每次都会触发 maven 增量编译(无改动约 47s,有改动 1-3 分钟)——
  这是正确性代价(本机 jdt.ls 不可信);
- `<leader>td`(Debug Nearest,断点调试)走 neotest-java 的 dap 策略,本轮未验证;
  需要断点调试时优先用 surefire suspend + DAP attach(nvim-jdtls#844 里的可靠路径)。

---

## 第三轮调查(2026-09-17 傍晚):断点不触发 + VS Code 式调试

### Q1:`<leader>tr` 跑测试时断点为什么不生效?

`<leader>tr` = `neotest.run.run()` 普通 process 策略:测试作为普通子进程执行
(java -jar junit-console),**没有调试器挂载**,nvim 里的断点不会传给 JVM。断点调试必须走
`<leader>td`(Debug Nearest,`neotest.run.run({ strategy = "dap" })`)。

### Q2:`<leader>td` 下断点仍不触发的根因(java-debug 0.53.2 行为)

DAP TRACE 日志显示 setBreakpoints 响应 `verified=false`(空 message)= 断点未绑定。
java-debug 0.53.2 的 `JdtSourceLookUpProvider.getBreakpointLocations`:**断点行必须精确落在
可执行语句行上;放在方法签名行会被判为无效位置,且不支持下移到下一有效行,直接 unverified、
永远不触发**(源码注释原文明说 "just mark it as unverified")。

实测:AbnActionCommandService.removeAbandon
- 断点在签名行 66 → verified=false,不触发
- 断点在方法体首语句行 67 → **stopped reason="breakpoint" 命中** ✓

结论:**把断点打到方法体内可执行语句行,不要打在方法签名行**。VS Code + 同版本
java-debug 有同样限制(其 UI 用空心圆提示 unverified,nvim 的 dap-ui/virtual-text
也会显示未验证状态,但容易忽略)。

### DAP 策略验证链(全部通过)

`<leader>td` → wrapper(maven 新鲜度检查)→ junit 命令注入
`-agentlib:jdwp=transport=dt_socket,server=y,suspend=y` → JVM 挂起等调试器 →
nvim-dap attach(java adapter 由 nvim-jdtls setup_dap 注册,LspAttach 时生效)→
断点命中 → dap-ui 自动打开(Scopes/Stacks/Watches/Repl ≈ VS Code 调试视图)。

wrapper 已加固:dap 策略下若产物被 jdt.ls 清空,取消本次运行并杀掉挂起 JVM
(避免 build_spec 重调泄漏第二个 suspend JVM),提示用户重按 <leader>td。

### 操作速查(Java 测试调试)

| 按键 | 作用 |
|---|---|
| <leader>tr | 跑最近测试(无调试) |
| <leader>td | 调试最近测试(断点生效,suspend=y + attach) |
| <leader>tD | 调试整个测试文件 |
| F5/F10/F11/F12 | 继续/单步跳过/单步进入/单步跳出(dap.core) |
| <leader>du | 切换 dap-ui(Scopes/Stacks/Watches/Console) |
| <leader>db | 切换断点(注意打在语句行,不要打在方法签名行) |

# LazyVim DAP 调试工具链补齐(VPS)

- **日期**:2026-09-12
- **运行环境**:Bandwagon VPS(`brave-goose-1`),LazyVim 栈按 [2026-09-07-1522-lazyvim-vps-replay](../2026-09-07-1522-lazyvim-vps-replay/spec.md) 已部署
- **性质**:系统环境变更(nvim 配置 + Mason 包,无业务代码)
- **状态**:已完成,DAP 接线 + LSP 回归全绿

## 背景与范围

用户要求"配置最新版 neovim + lazyvim + LSP + debug 工具"。盘点现状:

| 项 | 结论 |
|---|---|
| nvim | **v0.12.5 已是最新稳定版**(GitHub latest,2026-08-23 发布),无需升级 |
| LazyVim | sync 后 = **16.0.1**(latest),13 extras 不变 |
| LSP | 2026-09-07 已配好,本次只做回归验证 |
| **DAP** | **唯一缺口**:无 `dap.core` extra、无 debug 适配器 |

## 变更清单

| 变更 | 位置 | 说明 |
|---|---|---|
| 启用 `dap.core` extra | `~/.config/nvim/lazyvim.json` | nvim-dap + dap-ui + dap-virtual-text + mason-nvim-dap(`automatic_installation=true`,handlers 空) |
| Mason 新装 ×5 | `~/.local/share/nvim/mason/` | `debugpy`(提供 `debugpy-adapter` 可执行)、`delve` 1.27.2、`js-debug-adapter`、`java-debug-adapter`、`java-test`(后两者 java extra 的 ensure_installed 也会兜底) |
| TS/JS dap 配置 | `~/.config/nvim/lua/plugins/dap-js-ts.lua` | typescript extra **不带任何 dap 接线**,自写:`pwa-node` server 适配器(指向 Mason 包内 `js-debug/src/dapDebugServer.js`)+ js/ts/jsx/tsx 的 Launch file / Attach to process 配置 |

## 各语言接线方式(实测确认,LazyVim 16.0.1)

| 语言 | 接线 | 加载时机 |
|---|---|---|
| Python | python extra:nvim-dap-python 是 **nvim-dap 的 dependency**,`setup("debugpy-adapter")` | 随 nvim-dap 加载即挂 `adapters.python` |
| Go | go extra:nvim-dap-go 同为 nvim-dap dependency(且 ensure_installed delve) | 同上,挂 `adapters.delve` + `configurations.go` |
| Java | nvim-jdtls 从 Mason extra_bundles 自动注入 java-debug/java-test;dap.core 另提供 5005 远程 attach 配置 | jdtls 启动时 |
| Rust | rustaceanvim `get_codelldb_adapter(exepath, mason liblldb)` | ft=rust 时写入 `vim.g.rustaceanvim.dap.adapter` |
| TS/JS | **官方无**(typescript extra 不含 dap)→ 本次自写 | 随 nvim-dap 加载 |

## 验证(headless)

- **DAP**:`lazy.load({nvim-dap})` 后断言——`adapters.python/delve/pwa-node`、`configurations.go/typescript`、`vim.g.rustaceanvim.dap.adapter` 全部 true;6 个 Mason 包目录在位
- **二进制**:`dlv version` 1.27.2、`debugpy-adapter --help` 正常、`dapDebugServer.js` 存在(node v26.8.1)
- **LSP 回归**(复用 09-07 档案 lsp-check.lua 稳定等待法):py→pyright,ruff;ts→vtsls ✅
- 检查脚本快照:`/tmp/opencode/dap-check.lua`(临时,不归档;方法已写入本文)

## 坑与经验

1. **headless Mason 安装的 `Error in command line:` 噪音**:`+'luafile x.lua'` 后接自退出脚本时依旧打印此行,但脚本完整执行(所有 OK 行在)——判断成败看脚本自身输出,勿被首行吓退。
2. **dap 生态接线差异大**:python/go 把 nvim-dap-python/dap-go 挂在 nvim-dap 依赖下(**dap 加载即全配好**,与 ft 无关);rustaceanvim 才是 ft 惰性。headless 验证须区分加载时机,否则误报。
3. **mason-nvim-dap `automatic_installation` 只管 adapter 不管 configurations**:JS/TS 即使装了 js-debug-adapter 也无任何 launch 配置,必须自写(或项目放 launch.json)。

## 遗留

- Vue 浏览器端调试(pwa-chrome attach)未配,如需再补
- `~/.config/nvim` 在 VPS 上仍非 git 检出(09-07 档案已入 home-folder repo 3797f36,本机未 clone;本次新增 `dap-js-ts.lua` 与 lazyvim.json 改动**未入库**,需在 notebook 侧或本机 clone 后提交)
- java DAP 未做端到端断点实测(需真实 Maven/Gradle 项目,VPS 上暂无;接线与包在位已确认)

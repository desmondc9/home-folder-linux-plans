# LazyVim 学习工作区与 LSP 全家桶体检(调查 + 实施归档)

- **日期**:2026-09-04 ~ 09-05
- **性质**:教学工作区搭建 + 系统环境变更 + LSP 排查调查(无代码仓库变更)
- **状态**:已完成,全部验证通过

## 背景与目标

用 LazyVim 替代 IDE 作为日常编码编辑器。已知 Vim 基础(模式/移动/存退),LazyVim 工作流从零学起。教学遵循 teach-skill 工作流,产物在 `~/learning/lazyvim/`(不归档在本仓库,本档只存结论与环境变更)。

## 交付物:教学工作区 `~/learning/lazyvim/`

| 路径 | 内容 |
|---|---|
| `MISSION.md` / `NOTES.md` / `RESOURCES.md` | 使命(替代 IDE)、教学笔记、可信资源清单 |
| `lessons/0001~0004*.html` | 课程:①Space 菜单(文件/搜索/buffer)②读码循环(gd/gr/K/Ctrl+o)③编辑加速(flash/mini.ai/注释)④写入循环(cr/ca/co/cf);每课含按键模拟器+测验+实战 drill |
| `reference/lazyvim-core-keys.html` | 可打印速查表(对照官方 keymaps 校验,snacks-picker 时代) |
| `learning-records/0001~0004` | 学习记录:1~3 课均经自由回忆抽查验证通过 |
| `practice/` | 五语言(bug_hunt.{py,ts,go,java,rs})破坏性练习仓库,git 管理,`git checkout .` 复原 |

## 系统环境变更清单(迁移新机器按此重放)

| 变更 | 位置 | 说明 |
|---|---|---|
| **nvim 0.11.6 → 0.12.5** | `~/.local/lib/nvim-linux-x86_64/` + 软链 `~/.local/bin/nvim` | 系统包 0.11.6 未动;回滚 = 删软链。动因:rustaceanvim 硬性要求 ≥0.12 |
| **Go 1.27.1 工具链** | `~/.local/go/`(阿里云镜像) | `.zshrc` 追加 `PATH` + `GOPROXY=goproxy.cn` |
| **gopls v0.23.0** | Mason 包(权威)+ `~/.local/bin/gopls` | goproxy.cn 编译 |
| **rust-analyzer** | `rustup component add rust-analyzer` | 原先只有 rustup shim 存根,组件缺失(`Unknown binary` 报错) |
| **LazyVim extras ×13** | `~/.config/nvim/lazyvim.json` | go/java/json/markdown/python/rust/sql/terraform/toml/typescript/vue/yaml/git |
| **关闭保存时自动格式化** | `~/.config/nvim/lua/config/options.lua` 加 `vim.g.autoformat = false` | 手动 `Space c f` 生活方式 |
| Mason 包(28 个) | `~/.local/share/nvim/mason/` | 12 门语言 LSP + linter/formatter + codelldb(~100MB,走代理装) |

注意:`~/.config/nvim` 本身仍**不是 git 仓库**(多次建议 git init,尚未执行;lazy-lock.json 无版本化备份)。

## 排查结论(调查核心产出)

1. **Mason 的 `golang:` 类包 = 本地编译**:`go install pkg@version`,无 Go 工具链时**静默失败**(mason-core/installer/managers/golang.lua)。gopls 装不上的第一因。
2. **LazyVim 对 Mason 认识的服务器不自行 enable**:交给 mason-lspconfig `automatic_enable`,而它**只启用已安装的包**(LazyVim lsp/init.lua configure() 的 `use_mason` 分支)。"装不上 → 永远不挂载"连环坑由此而来。
3. **rustaceanvim 的 ftplugin 第一行硬门禁 `has('nvim-0.12')`**,0.11 下 notify_once 后直接 return,永不挂载且几乎无感。2026-09 生态(LazyVim main / lspconfig v3 / 新 nvim-jdtls)普遍按 0.12 设计,旧版 nvim 会陆续踩同类坑。
4. **root 探测链**(LazyVim root.lua):LSP workspace → 向上找 `.git`/`lua` → 兜底 cwd。从 `~` 裸启 nvim = 全盘扫描;口诀"先 cd 进项目再 nvim"。自查命令 `:lua =LazyVim.root.get()`;`Space fF` 按 cwd 搜。
5. **nvim-jdtls 新路径**(0.12):原生 `lsp/jdtls.lua`,`root_markers={.git,gradlew,mvw}` 严格匹配,裸目录不挂载(旧版宽松)。真实项目不受影响。
6. **LSP 不挂载标准诊断链**:`Space cl`(挂载?)→ `:Mason`(装了?)→ `~/.local/state/nvim/lsp.log`(报错?)。headless 自动化测试须等 **client 数量稳定**(pyright/vue_ls 是慢启动,"首个 client 即返回"会误报)。
7. **vtsls 一份管 js/jsx/ts/tsx**:LazyVim 无独立 javascript extra;`lang.typescript` 家族的 vtsls/tsgo 是 LSP 二选一,biome/oxc 是 lint/format 工具。

## 验证结果(nvim 0.12.5 下,headless 稳定等待法)

| 语言 | 挂载 |
|---|---|
| Python / Java / TS / Vue / Lua / Go / Rust | pyright+ruff / jdtls / vtsls / vue_ls+vtsls / lua_ls / gopls / rust-analyzer ✅ |
| JSON / YAML / TOML / Markdown / Terraform | jsonls / yamlls / taplo / marksman / terraformls ✅ |

## 参考

- 官方:<https://www.lazyvim.org/keymaps> · <https://www.lazyvim.org/configuration/lsp>
- 教学工作区:`~/learning/lazyvim/`(MISSION/NOTES/RESOURCES/lessons/practice)

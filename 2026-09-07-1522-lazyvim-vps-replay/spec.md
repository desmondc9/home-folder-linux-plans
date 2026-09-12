# LazyVim 在 Bandwagon VPS 的重放部署(按 2026-09-05-0040 清单)

- **日期**:2026-09-07
- 环境:Bandwagon VPS(Ubuntu,ssh 远程)
- **运行环境**:Bandwagon VPS(`brave-goose-1` / 104.194.83.82),Ubuntu Server 24.04,4C / 3.9G / 78G(当日二次升级后执行)
- **性质**:教育工作区系统环境重放(无代码仓库变更),母本:[2026-09-05-0040-lazyvim-learning-workspace](../2026-09-05-0040-lazyvim-learning-workspace/spec.md)(notebook)
- **状态**:已完成,6 语言 LSP 挂载验证通过

## 与母本的偏差(VPS 在美国,去掉国内中转)

| 母本(notebook) | 本次(VPS) |
|---|---|
| Go 阿里云镜像 + `GOPROXY=goproxy.cn` | **官方源直连**,GOPROXY 默认值,不设代理 |
| Mason 走 `127.0.0.1:10809` 代理 | 直连 |
| lazygit(源里有) | Ubuntu 24.04 无此包 → **GitHub 二进制**放 `~/.local/bin` |

## 变更清单(本机重放结果)

| 变更 | 位置 | 备注 |
|---|---|---|
| nvim **v0.12.5** | `~/.local/lib/nvim-linux-x86_64/` + 软链 `~/.local/bin/nvim` | 与母本同版本,满足 rustaceanvim ≥0.12 硬门禁 |
| Go **1.27.1** | `~/.local/go/` | `.zshrc` 追加 `~/.local/go/bin:$HOME/.cargo/bin` |
| rustup minimal + rust-analyzer | `~/.cargo/` | minimal profile(~400MB) |
| OpenJDK 21(jdtls 依赖) | apt `openjdk-21-jdk-headless` | 母本未记录 JDK 来源,本机用 apt |
| unzip / ripgrep / fd-find / lazygit 0.65.0 | apt + `~/.local/bin` | headless server 缺的基础件 |
| LazyVim starter + extras ×13 | `~/.config/nvim/`(`lazyvim.json`) | go/java/json/markdown/python/rust/sql/terraform/toml/typescript/vue/yaml + **lang/git**(注意:git 是 lang/ 下的 extra) |
| `vim.g.autoformat = false` | `lua/config/options.lua` | 同母本 |
| Mason 包 ×20 | `~/.local/share/nvim/mason/` | 含 gopls/jdtls/vtsls/vue-language-server/json-lsp 等 |

## 新坑(母本没有的)

1. **Mason 包名 `json-ls` 已不存在** → 现名 **`json-lsp`**;mason-lspconfig 的映射表改由 registry 包 spec 的 `neovim.lspconfig` 字段动态生成。反查法:`mr.get_all_package_specs()` 里找 `lspconfig == "jsonls"` 的包名。
2. **headless 引导必须等 Mason 队列清空再退出**:`+Lazy! sync` + `+qa` 会掐掉异步安装(golangci-lint 等 8 个包被中止)。正确姿势:`+'lua vim.wait(超时, function() …遍历 mason-registry,is_installing 全 false 才返回 true end, 2000)' +qa`;显式装包用 `mr.get_package(n):install()`(Lua API),`+MasonInstall a b c` 在 headless 命令行解析会报 "Error in command line"。
3. Ubuntu 24.04 无 lazygit 包,apt 对未知包名是**整条命令原子失败**(连带 unzip/jdk 一起没装)。

## 验证(client 数量稳定等待法,母本方法)

```
py -> pyright / ts -> vtsls / go -> gopls / java -> jdtls / vue -> vue_ls,vtsls / rust -> rust-analyzer
```

检查器脚本存档:本目录 `lsp-check.lua`(稳定 = client 数连续 3 次×2s 不变且 >0)。

## 遗留

- ~~`~/.config/nvim` 非 git 仓库~~ → **已补**(同日):配置入 `desmondc9/home-folder`(repo 根映射 `$HOME`,白名单 gitignore 加 `!.config/nvim/**`,提交 `3797f36`),VPS 与 notebook 共用;中间产物独立 repo `nvim-config` 已弃用待删(token 无 delete_repo 权,手动删)
- 教学工作区 `~/learning/lazyvim/`(lessons/practice)未迁移,属 notebook 侧资产;VPS 上按需 rsync

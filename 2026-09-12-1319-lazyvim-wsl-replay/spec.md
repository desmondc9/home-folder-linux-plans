# WSL 本机 LazyVim + LSP/DAP 重放(第三台机器)— 事后补记

- 日期:2026-09-12 13:19(session 实际 13:12–13:28,中断;本档案为事后补记)
- 类型:本机环境配置(无 repo 代码变更,无 PR)
- 状态:基本完成——session 中断于 LSP server 安装环节,后续交互式使用自动补齐;2026-09-12 17:55 复核通过(见「验证」)

## 环境

- **WSL2 Ubuntu**,宿主为 Windows 11 物理机(DESKTOP-J7NBNU4,mirrored networking)
- 参照档案:母本(Kubuntu)[2026-09-05-0040-lazyvim-learning-workspace](../2026-09-05-0040-lazyvim-learning-workspace/)、VPS 重放 [2026-09-07-1522-lazyvim-vps-replay](../2026-09-07-1522-lazyvim-vps-replay/);本机是第三台机器重放
- 网络直通 GitHub(宿主 sing-box TUN 分流),阿里云/rsproxy 国内镜像可达;当时本机无 GitHub 凭证

## 背景

参考 `~/plans` 已有档案,在本机配置最新版 Neovim + LazyVim,含 LSP 与 debug 工具链。因无 GitHub 凭证拉不到私有配置仓,改为 **LazyVim 官方 starter + 档案记载的 deltas**(extras ×13 + dap.core、autoformat=false)。

## 落地内容

- nvim v0.12.5(`~/.local`,与母本/VPS 同版)
- apt 补 `python3-venv`/pip(Mason 装 debugpy 的前置)
- Go 1.27.1(阿里云镜像)、rustup minimal(rsproxy 镜像,rust-analyzer 1.98.1)
- LazyVim 官方 starter 落位 `~/.config/nvim/`;`lazyvim.json` 14 个 extras(**全模块路径格式**)、autoformat=false
- shell 环境变量、fd 软链、win32yank(WSL 剪贴板)
- 本目录 4 个 headless 引导/诊断脚本(见「本目录工件」)装齐 5 个 debug 适配器 + tree-sitter-cli
- Windows 侧顺带以 **per-user** 方式装了 JetBrainsMonoNL NerdFont 16 权重——直接埋下当天下午的 WT 字体事故,见 [2026-09-12-1536-windows-terminal-font-not-found](../2026-09-12-1536-windows-terminal-font-not-found/)

## 关键坑(本档案的核心增量知识,前两台机器没遇到)

1. **lazyvim.json 的 extras 格式变了**:现行格式(v8 迁移后)要求**全模块路径** `lazyvim.plugins.extras.lang.go`;母本时代的相对写法 `lang.go` 会被自动加前缀成 `lazyvim.plugins.extras.extras.lang.go`(双前缀)而**全部失效**。更阴的是 LazyVim 迁移时会把错误条目原样重写持久化,`sd` 模式不匹配修不掉——最终读导入器源码(`config/init.lua:231`,按 `^lazyvim.plugins.extras%.` 匹配)实锤格式。症状:extras「看起来启用了」但 installed 计数不涨。
2. **headless 下 Mason 的 ensure_installed 不跑**:mason.nvim 是 `cmd="Mason"` 懒加载,其 `config` 才执行 `ensure_installed`,headless 无人触发 → extras 声明的包从未入队。修法:`require("lazy").load({plugins={"nvim-lspconfig","mason.nvim"}})` 强制加载让安装链跑起来。
3. **headless 等待判据必须含 `installing==0`**:第一轮只看「已装计数稳定」就退出,把还在异步安装的包掐了(debugpy/java-test 装一半)。
4. **交互式使用会自动补装 LSP servers**——headless 折腾不完的链路(mason-lspconfig 的 servers→packages),开 nvim 正常用就齐了;本机实际就是这么补完的。

## 验证(2026-09-12 17:55 复核)

- [x] nvim 0.12.5 / Go 1.27.1 / rustc 1.98.1
- [x] `lazyvim.json` 14 extras 全路径格式(dap.core + 13 lang)
- [x] Mason 27 包:LSP(pyright/ruff/gopls/jdtls/lua-language-server/json-lsp/marksman/tflint/sqlfluff)+ 5 个 DAP 适配器(codelldb/debugpy/delve/java-debug-adapter+java-test/js-debug-adapter)+ linters/formatters

## 遗留 / 跟进

- **vtsls 未装**(typescript extra 的默认 LSP 不在 Mason 列表)——若开 TS 项目需补
- home-folder 私有仓接入(当时无凭证)——后续 restic 灾备恢复已解决,plans 仓现已可读写
- WT 字体事故的修复见 [2026-09-12-1536-windows-terminal-font-not-found](../2026-09-12-1536-windows-terminal-font-not-found/)

## 本目录工件

| 文件 | 用途 |
|---|---|
| `mason-bootstrap.lua` / `mason-bootstrap2.lua` | headless Mason 引导(含等待判据从「计数稳定」到「installing==0 且计数稳定」的演进) |
| `mason-servers.lua` | 离线解析 14 个 extra 源码,提取 ensure_installed 并集与 LSP servers 清单 |
| `mason-diag.lua` | Mason 状态诊断(不过滤输出,防真实报错被 grep 吃掉) |

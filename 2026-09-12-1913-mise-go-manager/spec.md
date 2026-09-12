# mise 接管 Go 版本管理(Rust 保持 rustup)

- 日期:2026-09-12 19:13
- 类型:本机环境配置(无 repo 代码变更,无 PR)
- 状态:已完成并验证(新 shell + 删旧目录后复验通过)

## 环境

- **WSL2 Ubuntu**(宿主 Windows 11 物理机 DESKTOP-J7NBNU4,mirrored networking)
- shell:zsh;已有版本管理器:nvm 0.40.7(node)、sdkman(java)、uv(python)
- 网络:GitHub 直通(宿主 sing-box TUN 分流);mise 安装 go 走 dl.google.com,按约定**预先**注入 `127.0.0.1:10809` 代理

## 背景

用户要求安装最新 Go/Rust,并询问有无 nvm/uv 式的版本管理器。现状核查(当天下午 lazyvim-wsl-replay 已装):Go 1.27.1 手动装在 `~/.local/go`、Rust 1.98.1 stable 由 **rustup** 管理——两者均已是最新。

结论(设计决策):
- **Rust:rustup 本身就是官方的 nvm 式管理器**(多 toolchain 共存、项目级 `rust-toolchain.toml`、`rustup update`),没有更好的替代,mise 管 Rust 也是底层调 rustup → **保持不动**
- **Go:无官方管理器,gvm/goenv 已过时,选 mise**(asdf 继任者,Rust 实现):全局 `mise use -g go@x.y` + 项目级 `.mise.toml` 锁版本,与 nvm/uv 使用习惯一致;**只接管 Go**,nvm/sdkman/uv 保持现状,将来想统一再逐个迁(YAGNI)

## 变更内容

| 项 | 前 | 后 |
|---|---|---|
| Go 供给 | `~/.local/go` 手动安装(282MB) | `mise use -g go@1.27.1` → `~/.local/share/mise/installs/go/1.27.1/` |
| `.zshrc` | `export PATH="$HOME/.local/go/bin:$PATH"` | `eval "$(mise activate zsh)"` |
| GOPROXY | `goproxy.cn,...`(保留不动) | 同左 |
| mise 本体 | 无 | `curl https://mise.run \| sh` → `~/.local/bin/mise`(2026.9.5) |
| Rust | rustup 1.98.1 stable | 不变 |
| `~/.claude/CLAUDE.md` | 无 mise 条目 | Preferred CLI tools 小节登记 mise/rustup 管理约定(never install Go by hand;opencode 经 AGENTS.md 符号链接同享) |

关键无害性依据:**GOPATH 默认仍是 `~/go`**(工具缓存/未来 `go install` 落点不变),且 `~/go/bin` 本来为空——gopls/gofumpt/goimports/golangci-lint 都由 Mason 装在自己的 bin(`~/.local/share/nvim/mason/bin/`)里,nvim LSP 链路零影响。

## 验证

- [x] 新 shell:`which go` → mise installs 路径;`go version` → 1.27.1;GOPATH/GOPROXY 不变
- [x] `mise doctor`:shims on path,无问题
- [x] Mason bin:gopls/gofumpt/goimports/golangci-lint 在位
- [x] 删除 `~/.local/go`(282MB)后复验 `go version` 正常

## 日常用法速查

```bash
mise use -g go@latest        # 升级全局 go
mise use go@1.26.0           # 项目目录下生成 .mise.toml 锁版本
mise ls; mise upgrade go     # 查看/升级
rustup update stable         # Rust 侧等价操作(rustup 官方)
rustup toolchain install nightly && rustup override use nightly  # 项目切 nightly
```

## 参考

- mise: https://mise.jdx.dev/
- rustup: https://rustup.rs/

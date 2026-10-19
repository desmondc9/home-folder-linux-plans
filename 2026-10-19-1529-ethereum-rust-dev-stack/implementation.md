# 实施记录

对应 [spec.md](spec.md) · 日期:2026-10-19 · 全部当日完成并验证

## 已完成

- [x] 排查 `solana` command not found(证据链见 spec.md,根因:安装器写 `~/.profile`,zsh 不读)
- [x] 修复 PATH:向 `~/.zshrc` 末尾追加 solana export(见下方变更清单);`~/.profile` 旧配置保留
- [x] Solana 工具链验证(zsh -ic 全绿):rustc/cargo 1.99.1、solana-cli 3.1.10、anchor-cli 1.1.2、surfpool 1.6.1、node v26.10.0(nvm)、yarn 1.22.22
- [x] Ethereum Rust 工具链调研(后台 research agent,37 条来源全部于 2026-10-19 访问核实,事实与判断分开标注)→ 全文存档 `~/docs/ethereum-rust-dev-stack.md`

## 变更清单(本会话产生的改动)

| 文件 | 变更 |
|---|---|
| `~/.zshrc` | 末尾追加 2 行:`# Solana CLI (installer wrote this into ~/.profile, which zsh never reads)` + `export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"`(回滚:删除这 2 行即可) |
| `~/docs/ethereum-rust-dev-stack.md` | 新建,调研全文(概念纠正 + 按 feature 选型 + 对照/速查表 + 来源列表);按 `~/docs` 惯例该目录不入 git |
| `~/plans/2026-10-19-1529-ethereum-rust-dev-stack/` | 本条目(spec.md + implementation.md) |

## 验证记录

```console
$ zsh -ic 'command -v solana && solana --version'
/home/desmond/.local/share/solana/install/active_release/bin/solana
solana-cli 3.1.10 (src:7bc9c805; feat:1620780344, client:Agave)

$ zsh -ic 'rustc --version; anchor --version; surfpool --version; node --version; yarn --version'
rustc 1.99.1 (58cf8f9c3 2026-10-13)
anchor-cli 1.1.2
surfpool 1.6.1
v26.10.0
1.22.22
```

(沙箱无 TTY 引起的 `zle` 警告已从输出中过滤,真实终端不出现。)

## 遗留 / 后续

- 尚未运行 `solana-keygen new`,首次 `solana address` 会报缺密钥对(预期行为)
- Stylus activation 暂停(2026-02 起)为时效性风险,若后续考虑 Stylus 路径需先查 [暂停公告](https://docs.arbitrum.io/notices/stylus-activation-pause-notice) 是否解除
- 若希望调研全文也纳入版本控制,可考虑将 `~/docs` 并入某个 git 仓库(当前 `~/docs` 整目录不在任何仓库中,属既有惯例,未改动)

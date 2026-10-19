# Solana 开发环境搭建(zsh 不读 ~/.profile 的 PATH 坑)与 Ethereum Rust 工具链调研

日期:2026-10-19 15:29 · 状态:**已完成并验证**(PATH 修复当日 `zsh -ic` 实测通过;调研报告存档于 `~/docs/ethereum-rust-dev-stack.md`)· 实施记录:[implementation.md](implementation.md)
- 环境:Windows 宿主 + WSL2 Ubuntu(kernel `6.18.54.1-microsoft-standard-WSL2`),登录 shell `/bin/zsh`
- 起因:用户经 `https://solana-install.solana.workers.dev` 安装脚本装好 Solana CLI 后,新终端执行 `solana address` 报 command not found;随后要求排查其余 CLI,并调研"基于 Rust 的 Ethereum 开发各 feature 用什么框架"

## 任务

1. 排查新终端找不到 `solana` 命令的原因并修复
2. 验证整套 Solana 工具链在 zsh 中可直接调用
3. 调研 Ethereum/EVM 生态中,面向 Rust 开发者的各环节框架选型(对照 Solana 栈)

## PATH 问题诊断:安装器写 ~/.profile,但登录 shell 是 zsh

### 证据链(命令 → 输出 → 推论)

| # | 命令 | 实际输出(摘) | 推论 |
|---|---|---|---|
| 1 | `ls -la ~/.local/share/solana/install/` | `active_release -> .../releases/3.1.10/solana-release` | 安装本体成功,二进制齐全 |
| 2 | `~/.local/share/solana/install/active_release/bin/solana --version` | `solana-cli 3.1.10 ...` | 二进制可执行,排除安装损坏 |
| 3 | `rg solana ~/.zshrc ~/.zprofile ~/.zshenv ~/.bashrc ~/.profile ~/.bash_profile` | 仅 `~/.profile:30` 命中一行 `export PATH=...` | 安装器把 PATH 写进了 `~/.profile` |
| 4 | `getent passwd desmond` | shell 为 `/bin/zsh`;且 `~/.zprofile`、`~/.bash_profile` 均不存在 | zsh 只读 `.zshenv/.zprofile/.zshrc/.zlogin`,**从不读 `~/.profile`**,也没有 zprofile 桥接 sourcing 它 |

### 结论与修复

- **根因**:`solana-install` 安装脚本统一把 PATH export 写进 `~/.profile`,在 bash 登录 shell 下成立,但在 zsh 下该文件永不加载 ⇒ 每个新终端都找不到 `solana`。
- **修复**(`~/.zshrc` 末尾追加,置于 gcloud 别名之后):

  ```bash
  # Solana CLI (installer wrote this into ~/.profile, which zsh never reads)
  export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
  ```

- **验证**:`zsh -ic 'command -v solana && solana --version'` → 解析到 `~/.local/share/solana/install/active_release/bin/solana`,`solana-cli 3.1.10`。(输出中的 `zle` 警告系无 TTY 沙箱所致,真实终端不出现。)
- `~/.profile` 里的旧配置保留无害(万一经 bash/sh 登录仍可用),未删除。
- **可推广教训**:安装器声称"PATH 已配置"时,先核对它写入的文件 × 登录 shell 实际加载的文件。zsh:`.zshenv/.zprofile/.zshrc/.zlogin`;bash 登录:`.bash_profile/.bash_login/.profile`。同类坑适用一切写 `.profile` 的安装器(rustup 曾同源中招,见本机 `~/.cargo` 相关配置)。

## Solana 工具链验证结果(全部可直接调用)

经 `zsh -ic`(等价新开终端)逐项验证,版本与预期清单一致:

| 工具 | 版本 | 路径 |
|---|---|---|
| Rust | rustc/cargo 1.99.1 | `~/.cargo/bin`(rustup) |
| Solana CLI | solana-cli 3.1.10 | `~/.local/share/solana/install/active_release/bin`(本次修复) |
| Anchor CLI | anchor-cli 1.1.2 | `~/.cargo/bin`(cargo 安装) |
| Surfpool CLI | surfpool 1.6.1 | `~/.local/bin` |
| Node.js | v26.10.0 | `~/.nvm/versions/node/v26.10.0/bin`(nvm) |
| Yarn | 1.22.22 | 同上 |

`solana-test-validator` 与 solana-cli 同目录,随之可用。备注:尚未生成密钥对,`solana address` 前需先 `solana-keygen new`。

## Ethereum 调研核心结论(全文含 37 条来源见 `~/docs/ethereum-rust-dev-stack.md`,2026-10-19 逐条核实)

### 概念纠正(影响选型全局)

- "Rust 参与 Ethereum 开发"是两条路径:① 合约层写 Solidity,工具链全是 Rust 写的(Foundry/alloy/revm/reth,L1 绝对主流);② 合约层直接用 Rust —— 唯一生产路径 **Arbitrum Stylus**(Rust→WASM),仅 Arbitrum L2,不能部署到 Ethereum L1。
- **Solang 不是 Rust→EVM 编译器**:它是 Rust 写的 Solidity 编译器,目标链 Solana/Polkadot/Stellar,无 EVM target(Hyperledger 维护,v0.4.0 @ 2026-09-30)。
- **Stylus 时效性风险**:2026-02-10 起 Arbitrum One/Nova 新 Stylus 合约 activation 被安全委员会暂停,2026-09-02 基金会进展帖确认仍未恢复;测试网(Arbitrum Sepolia)可正常开发。恢复前新项目勿押核心合约。
- ink! 只面向 Polkadot 且 2026-01 起停止维护,排除。

### Solana 栈 → Ethereum 栈对照(速查)

| 环节 | Solana(现有) | Ethereum 对应 |
|---|---|---|
| 合约语言/框架 | Rust + Anchor | Solidity + **Foundry**(v1.0 @ 2025-02,现行 v1.8.5) |
| 本地测试链 | test-validator + Surfpool | **anvil**(本地链 + fork 主网 + cheatcodes + 时间操控) |
| 进程内执行/单测 | litesvm / mollusk | **revm** 43.x(+ `alloy-evm`) |
| CLI | solana-cli | **cast**(查链/发交易)+ **forge**(构建/测试/部署) |
| Rust SDK | @solana/kit | **alloy** 2.5.x(ethers-rs 已归档弃维,web3.rs "barely maintained") |
| 签名器 | kit-plugin-wallet | **alloy-signer-***(local/aws/gcp/ledger/trezor) |
| ABI/IDL bindings | Anchor IDL 生成 | **`sol!` 宏** / `forge bind`(typechain-rs 已消亡) |
| 部署 | anchor deploy | **forge script**;复杂编排用 alloy 纯 Rust 脚本 |
| 模糊测试 | 无官方内建 | **forge fuzz / invariant**(+ mutation/symbolic MVP) |
| 全节点/索引 | geyser 等 | **reth** 2.7(自建 RPC/ExEx)、Substreams(重度索引)、alloy pubsub(轻量) |
| ERC-4337(Rust) | — | **Rundler**(Alchemy 生产使用;silius 维护放缓) |

### 推荐组合

**Foundry(forge + cast + anvil)+ alloy + OpenZeppelin Contracts**,按需加 revm(进程内测试)与 reth(自建基础设施)。除 Solidity 合约本身外全栈 Rust,与 Solana 侧 "CLI + Anchor + 模拟器 + SDK" 心智模型一一对应。合约层必须 Rust 时,Stylus 仅作特定场景备选(计算密集且只部署 Arbitrum),当前受 activation 暂停制约。

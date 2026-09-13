# git clone 未使用本地代理导致速度慢 —— 修复方案

- 日期:2026-07-30(原 mac 档案仅记日期;HHMM 取 mac 仓库入库 commit 时间)
- 环境:macOS(Apple Silicon MacBook;本地代理 127.0.0.1:10809,git HTTP/SSH 双协议)
- 类型:本机网络/git 配置修复(无 repo 代码变更,无 PR)
- 状态:已完成并验证

## 背景与目标

用户反馈从 GitHub `git clone` 速度非常慢，怀疑本地代理（`127.0.0.1:10809`）没有生效。目标是定位根本原因并修复，使 `git clone`/`fetch`/`pull` 等操作能稳定走本地代理加速。

本任务为单机环境配置修复，非某个代码仓库内的功能开发，因此不涉及 `~/CLAUDE.md` 工作流中 Kanban 关联、`git worktree`、Gherkin/E2E、PR 提交等环节；仅保留 spec.md / implementation.md 的记录方式。

## 范围

- **In scope**：诊断 `git clone` 未走代理的原因；修复 git 自身代理配置；修复交互式 shell（zsh）的代理环境变量持久化；修复 SSH 协议（`git@github.com`）克隆卡死的问题。
- **Out of scope**：无（原计划中 SSH 协议不需要配置的判断，经二次实测后证明有误，已纳入 in scope，见下）。

## 现状分析（Root Cause）

1. 当前 Claude Code 工具沙箱会话的环境变量中已经存在 `http_proxy` / `https_proxy` / `all_proxy`（大小写两套），且代理端口 `127.0.0.1:10809` 探测正常、`curl` 走代理访问 GitHub 200 OK。
2. 但检索 `~/.zshrc`、`~/.zprofile`、`~/.bash_profile`、`~/.bashrc` 后，**没有任何地方导出这些代理变量**——它们只存在于当前工具会话的注入环境里，用户在真实终端（普通 zsh 交互 shell / 登录 shell）里执行命令时并不会拿到这些变量。
3. `git config --global --list` 中也没有配置 `http.proxy` / `https.proxy`。
4. 结论：用户真实终端里的 `git clone` 完全没有代理可用，走的是裸连 GitHub，因此慢/不稳定。代理服务本身工作正常，问题出在"代理没有传达给 git 进程"。

### 补充发现：SSH 协议单独踩坑（二次验证时发现）

首次验证时用 `ssh -T git@github.com` 测试握手，约 2s 内返回认证成功，误判为"SSH 未被限速、无需配置"。但实际执行 `git clone git@github.com:apache/flink.git`（真实数据传输）时**卡死超过 3 分钟无响应**。

原因：SSH 认证握手数据量极小，探测不出限速；真正的对象打包传输走的是完全独立于 HTTP(S) 的通道，`http_proxy`/`https_proxy`/git 的 `http.proxy` 配置对 SSH 协议完全不生效，必须单独通过 `~/.ssh/config` 的 `ProxyCommand` 把 SSH 流量转发到本地代理。

## 解决方案

采用双保险，覆盖"git 自身配置"和"shell 环境变量"两条路径：

1. **git 全局代理配置**（不依赖 shell 环境变量，GUI git 客户端等场景也生效）：
   ```
   git config --global http.proxy http://127.0.0.1:10809
   git config --global https.proxy http://127.0.0.1:10809
   ```
2. **`~/.zshrc` 追加代理环境变量导出**（对齐 `~/CLAUDE.md` 中"网络访问代理"章节给出的标准代理变量块），确保新开的交互式 / 登录 shell 都能拿到：
   ```
   export http_proxy="http://127.0.0.1:10809"
   export https_proxy="http://127.0.0.1:10809"
   export all_proxy="socks5://127.0.0.1:10809"
   export HTTP_PROXY="http://127.0.0.1:10809"
   export HTTPS_PROXY="http://127.0.0.1:10809"
   export ALL_PROXY="socks5://127.0.0.1:10809"
   ```
3. **`~/.ssh/config` 为 github.com 配置 `ProxyCommand`**（使用 macOS 自带 `nc` 的 SOCKS5 支持，转发到本地代理）：
   ```
   Host github.com
       HostName github.com
       User git
       ProxyCommand nc -x 127.0.0.1:10809 -X 5 %h %p
       ServerAliveInterval 30
   ```

## 验收标准

- [x] `git config --global --get-regexp '.*proxy.*'` 显示 `http.proxy` 与 `https.proxy` 已设置为 `http://127.0.0.1:10809`。
- [x] 新开的 `zsh -l` 登录 shell 中 `echo $http_proxy` / `$https_proxy` 能正确输出代理地址。
- [x] `git clone --depth=1 https://github.com/git/git.git` 在几秒内完成（实测约 5s）。
- [x] `git clone https://github.com/apache/flink.git`（完整仓库，848M，26858 文件）实测约 37s 完成，验证 HTTPS 路径在真实大仓库场景下有效。
- [x] SSH 协议：配置 `ProxyCommand` 前，`git clone --depth=1 git@github.com:apache/flink.git` 卡死 3 分钟无响应（仅认证握手快，数据传输被限流）。
- [x] SSH 协议：配置 `ProxyCommand` 后，同样的 shallow clone 实测约 18.3s 完成。

## 风险与缓解

- 若本地代理服务（127.0.0.1:10809）停止运行，git 网络操作会失败而非降级为直连。缓解：`~/CLAUDE.md` 已约定"若代理和镜像都失败，先确认本地代理是否真的在运行"的排查顺序。
- 全局 `git config` 代理会对所有仓库生效，包括公司内网的 Azure DevOps 仓库。目前该地址通过 `url.insteadof` 走 SSH（`git@ssh.dev.azure.com`），不受 HTTP(S) 代理配置影响，暂无冲突。
- `~/.ssh/config` 中的 `ProxyCommand` 仅对 `Host github.com` 生效，不影响 `ssh.dev.azure.com` 等其他 Host 的直连行为。
- `nc -X 5` 依赖本地 SOCKS5 代理（`all_proxy=socks5://127.0.0.1:10809`）保持运行；若该代理服务下线，SSH 协议的 GitHub 访问会连接失败（而非静默降级为直连）。

## 参考

- `~/CLAUDE.md` "网络访问" 章节（mainland China 代理约定）。

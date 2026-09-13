# Implementation: git clone 未使用本地代理 —— 修复

对应 spec.md 的全部范围（单阶段，无需拆分 phase）。

## 依赖

无（本机环境配置，不依赖其他任务）。

## 任务列表

- [x] 诊断：确认代理端口 `127.0.0.1:10809` 存活，`curl -x` 走代理访问 GitHub 返回 200。
- [x] 诊断：检索 `~/.zshrc` / `~/.zprofile` / `~/.bash_profile` / `~/.bashrc`，确认代理变量未持久化导出。
- [x] 诊断：确认 `git config --global` 未设置任何 `*.proxy`。
- [x] 修复：`git config --global http.proxy http://127.0.0.1:10809`
- [x] 修复：`git config --global https.proxy http://127.0.0.1:10809`
- [x] 修复：在 `~/.zshrc` 末尾追加代理环境变量导出块（http/https/all，大小写各一套）。
- [x] 验证：`git config --global --get-regexp '.*proxy.*'` 输出符合预期。
- [x] 验证：`zsh -l -c 'echo $http_proxy; echo $https_proxy'` 输出符合预期。
- [x] 验证：`git clone --depth=1 https://github.com/git/git.git` 实测约 5s 完成。
- [x] 验证：真实场景 `git clone https://github.com/apache/flink.git`（完整仓库）克隆到 `~/Repos/flink`，实测约 37s 完成。
- [x] 复测：`ssh -T git@github.com` 约 2s 完成握手 → 一度误判 SSH 无需代理配置。
- [x] 复测发现问题：`git clone --depth=1 git@github.com:apache/flink.git`（真实数据传输）卡死 3 分钟无响应，证明 SSH 数据通道被限流，握手测试不足以验证。
- [x] 修复：新增 `~/.ssh/config`，为 `Host github.com` 配置 `ProxyCommand nc -x 127.0.0.1:10809 -X 5 %h %p`，将 SSH 流量转发到本地 SOCKS5 代理。
- [x] 验证：配置后 `ssh -T git@github.com` 认证仍然成功；`git clone --depth=1 git@github.com:apache/flink.git` 实测约 18.3s 完成。

## 变更文件

| 文件 | 变更内容 |
|------|----------|
| `~/.gitconfig`（通过 `git config --global`） | 新增 `http.proxy` / `https.proxy` = `http://127.0.0.1:10809` |
| `~/.zshrc` | 末尾追加 6 行代理环境变量 `export`（`http_proxy`/`https_proxy`/`all_proxy` 及大写版本） |
| `~/.ssh/config`（新建） | 为 `Host github.com` 配置 `ProxyCommand nc -x 127.0.0.1:10809 -X 5 %h %p`，`chmod 600` |
| `~/.ssh/known_hosts` | 通过 `ssh-keyscan -t rsa,ed25519 github.com` 追加 GitHub host key，避免 clone 时卡在 host 确认 |

## 配置变更详情

无 API / 数据库变更。涉及的配置变更已在上表列出，具体内容见 spec.md「解决方案」章节的代码块。

## 验证方式

- `git config --global --get-regexp '.*proxy.*'`
- 新开终端或 `source ~/.zshrc` 后 `echo $http_proxy`
- 实际执行一次 `git clone` 小型仓库计时对比

## 备注

- 本任务未创建 `git worktree` / 分支 / PR，因为改动对象是用户本机环境配置文件（`~/.gitconfig`、`~/.zshrc`、`~/.ssh/config`），不属于任何代码仓库内的功能开发，`~/CLAUDE.md` 工作流中 Kanban 关联、Gherkin/E2E、文档同步等步骤不适用。
- **教训**：验证网络代理是否生效时，仅测试握手/认证（如 `ssh -T`）不够，必须实测真实的数据传输场景（如实际 `git clone` 一个有一定体量的仓库），否则会得出"看似正常"的错误结论。本任务中 SSH 协议就是先被误判为"无需代理"，二次用真实 clone 验证才发现问题。

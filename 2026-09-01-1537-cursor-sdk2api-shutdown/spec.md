# cursor-sdk2api 本地网关下线 — 设计规格

- **日期**: 2026-09-01 15:37–16:0x CST
- **作者**: Desmond(与 Claude brainstorming 产出)
- **性质**: 家目录系统配置任务(bounded);无 Kanban 工作项(个人环境,非项目仓库改动)

## 1. 背景与动机

`cursor-sdk2api`(https://github.com/Sunnyender-org/cursor-sdk2api)是一个 Node 网关,把官方 `@cursor/sdk` 封装成 Anthropic 兼容 HTTP API,以 systemd user unit 常驻本机 127.0.0.1:8080,供 `ccw --provider=cursor-sdk2api` 使用。

**下线动因**:它经常出错、不如 cursorbridge.dev 稳定。journal 近 7 天 55 条 warn/error,典型故障:

```
403 forbidden: Model claude-haiku-4-5-20251001 is unavailable across the configured Cursor accounts
```

即 Claude Code 后台请求点名 Haiku 档模型,而账号池供不出 → 请求直接失败。换 cursorbridge.dev(第三方 Cursor 账号代理,自带模型映射)后该类问题不再依赖本地账号池。

**决策**:关闭本地网关,主力出口改为 `ccw --provider=cursorbridge`。

## 2. 现状盘点(下线前)

| # | 组件 | 位置 | 状态 |
|---|------|------|------|
| 1 | systemd user unit | `~/.config/systemd/user/cursor-sdk2api.service` | enabled,常驻,127.0.0.1:8080 |
| 2 | 运行时配置 | `~/.config/cursor-sdk2api/gateway.env`(600) | HOST/PORT/AUTH_MODE/GATEWAY_ACCESS_KEY(`csk_***`)/STATE_DIR/LOG_LEVEL |
| 3 | 持久状态 22MB | `~/.local/share/cursor-sdk2api/state` | auths(Cursor 账号池凭据)/sdk-store/lineage/ordinary-trace |
| 4 | 上游 clone 176MB | `~/Repos/cursor-sdk2api` | main@1e18349 干净;含 2026-09-01 02:40 的 worktree `feature/cursor-sdk2api-aca-deploy`(无独有提交,内有一份未提交 ACA 部署 spec) |
| 5 | fork clone 174MB | `~/Repos/desmondc9-cursor-sdk2api` | `fix/stream-error-message-stop`@79c6396,**已推 GitHub fork** |
| 6 | ccw 接线 | `~/.zshrc` ccw 函数 | `cursor-sdk2api` provider 分支(localhost:8080 + `csk_***`);`cursorbridge` 分支已存在可用 |

**安全性前置确认**:
- 当时在跑的两个 claude 会话均走 bigmodel GLM 直连(`open.bigmodel.cn`),不依赖 8080;
- pts/6 的 `~/.local/bin/agent`(cursor-agent CLI)为用户手动开的交互会话,父进程是普通 zsh,与网关无关;
- ⇒ 停服不影响任何运行中的进程。

## 3. 范围

**做**(用户三项确认:停用+删服务但留 repo;ACA spec 直接丢弃;STATE_DIR 凭据不备份直接删):
1. `systemctl --user disable --now cursor-sdk2api.service`
2. 删 unit 文件 + `daemon-reload` + `reset-failed`
3. 删 `~/.config/cursor-sdk2api/`(gateway.env,含网关访问密钥)
4. 删 `~/.local/share/cursor-sdk2api/`(22MB,含 Cursor 账号池凭据——不可逆,已确认)
5. `git worktree remove --force` + `git branch -D feature/cursor-sdk2api-aca-deploy`(丢弃 ACA spec;分支无独有提交,零代码损失)
6. 编辑 `~/.zshrc`:删 ccw 的 `cursor-sdk2api)` case 分支,同步改函数头注释与 unknown-provider 提示;改前备份 `/tmp`

**不做**:
- 两个 repo clone 保留在 `~/Repos/`(fork 修复提交 `79c6396` 已在 GitHub,随时可找回);
- GitHub fork(desmondc9/cursor-sdk2api)保留;
- `~/.claude.json` 的 `githubRepoPaths` 两条记录无害,不动;
- 交互式 cursor-agent 会话不动。

## 4. 验收标准

- [x] `systemctl --user status cursor-sdk2api` → unit 不存在;`ss -ltn` 无 :8080 监听
- [x] `zsh -n ~/.zshrc` 语法通过;`rg sdk2api ~/.zshrc` 零命中
- [x] 新 shell 中 `ccw --provider=cursor-sdk2api` → 报 unknown provider,exit 2,不触碰 claude
- [x] cursorbridge.dev 出口实测可用(1-token 最小请求,HTTP 200)

## 5. 残留与恢复路径

- **恢复方式**(若将来想再跑):clone GitHub fork(`desmondc9/cursor-sdk2api`,含 stream-error 修复),按其 README 起 docker-compose 或 node;账号池凭据已删,需重新导入 Cursor 账号;ccw 分支需按本 spec §2.6 的旧行为重写(NO_PROXY 保 loopback)。
- **丢弃物**:ACA 部署 spec(2026-09-01 02:40 worktree 内 `plans/`),用户确认随下线废弃。
- **操作注意(新发现)**:cursorbridge.dev 从本机**直连超时(curl 28,25s)**,走 `127.0.0.1:10809` 代理即 200。`.zshrc` 的代理导出默认注释——用 `ccw --provider=cursorbridge` 前需先在 shell 里 export 代理(CLAUDE.md 有现成片段)。

## 6. 性能与容量(Step G verify gate)

**不触发**:纯本机服务下线 + shell 配置编辑,无 SQL/查询/批写/缓存/外呼代码路径变更;唯一外呼为验收用的一次性 curl(经代理)。无新增性能债。

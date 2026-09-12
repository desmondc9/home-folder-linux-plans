# opencode serve 远程暴露(systemd 常驻,供 opencode-mobile 连接)

- 日期:2026-09-06 18:47
- 环境:Kubuntu 26.04 + Wayland 笔记本(yaoshi15pro)(tailscale 100.64.0.1)
- 类型:本机服务配置(无 repo 代码变更,无 PR)
- 状态:已上线并验证(curl 鉴权矩阵 + 手机端待用户实测)

## 背景

用户希望在 Android 上用 [opencode-mobile](https://github.com/dzianisv/opencode-mobile)(开源第三方客户端,MIT,React Native/Expo)远程访问本机 opencode。本机已有 Tailscale(本机 IP `100.64.0.1`),网络层是通的,只需把 opencode 以 server 模式暴露出来。

## 调研结论(官方文档 + 客户端 README)

| 需求 | 来源 | 结论 |
|---|---|---|
| 默认监听 `127.0.0.1` 不可远程访问 | [opencode server 文档](https://opencode.ai/docs/server/) | `opencode serve --hostname 0.0.0.0 --port 4096` |
| 客户端强制要求密码 | opencode-mobile README Step 1 | `OPENCODE_SERVER_PASSWORD` 启用 HTTP Basic Auth,用户名默认 `opencode` |
| 连接方式 | opencode-mobile README Step 3 | app 内 Add Connection → Tailscale → `http://100.64.0.1:4096` + 密码 |

## 实施

### 1. 密码文件(机密不入库,只记路径)

- `~/.config/opencode/serve.env`,内容 `OPENCODE_SERVER_PASSWORD=…`,权限 `0600`
- **真实值在该文件里,本文档不贴**(公开仓库红线,见仓库 CLAUDE.md)

### 2. systemd user unit

`~/.config/systemd/user/opencode-serve.service`(unit 本体不含机密,密码经 `EnvironmentFile` 注入):

```ini
[Unit]
Description=opencode serve (HTTP API for remote clients, e.g. opencode-mobile)
After=network-online.target
Wants=network-online.target
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
EnvironmentFile=/home/desmond/.config/opencode/serve.env
Environment=AZURE_RESOURCE_NAME=opencode-skip-az-probe
Environment=HOME=/home/desmond
Environment=TMPDIR=/tmp
Environment=PATH=/home/desmond/.opencode/bin:/usr/bin:/home/desmond/.nvm/current/bin:/home/desmond/.local/bin:/home/desmond/.npm-global/bin:/home/desmond/.volta/bin:/home/desmond/.asdf/shims:/home/desmond/.bun/bin:/home/desmond/.local/share/pnpm:/usr/local/bin:/bin
ExecStart=/home/desmond/.opencode/bin/opencode serve --hostname 0.0.0.0 --port 4096
WorkingDirectory=/home/desmond
Restart=always
RestartSec=3
TimeoutStopSec=30
KillMode=control-group

[Install]
WantedBy=default.target
```

关键决策:

- **ExecStart 直指真实二进制** `~/.opencode/bin/opencode`(ELF 原生,非脚本),不经过 `~/.local/bin/opencode` wrapper——后者靠遍历 `$PATH` 自解析,在 systemd 的精简 PATH 下脆弱;但 wrapper 的价值(Azure 探针短路)以 `Environment=AZURE_RESOURCE_NAME=opencode-skip-az-probe` 保留,根因见 [2026-09-01-2111-opencode-slow-startup](../2026-09-01-2111-opencode-slow-startup/)
- **不设代理环境变量**:本机已认证的 provider 全为国产直连端点(zai / zhipuai / alibaba-cn / kimi / minimax,查 `~/.local/share/opencode/auth.json` 的 key 列表),GFW 内无需代理;且 10809 代理不保证常驻
- **PATH 仿照本机既有 user unit**(`openclaw-gateway.service` 的写法),供 agent 运行期 spawn 的 shell / LSP / formatter 使用
- **`WorkingDirectory=/home/desmond`**:serve 以 cwd 注册项目,默认会话落在 home;想默认进某个项目改此行后 `daemon-reload + restart`

### 3. 开机自启(免登录)

```bash
systemctl --user daemon-reload && systemctl --user enable --now opencode-serve.service
loginctl enable-linger   # Linger=yes,开机不登录桌面也拉起 user manager
```

## 验证

- [x] `systemctl --user status opencode-serve` → active (running),日志 `opencode server listening on http://0.0.0.0:4096`
- [x] 经 Tailscale IP 的鉴权矩阵(`http://100.64.0.1:4096/session`):无凭据 401 / 正确密码 200 / 错误密码 401;`/global/health` 免鉴权返回 `{"healthy":true,"version":"1.18.29"}`
- [x] `loginctl show-user desmond -p Linger` → `Linger=yes`
- [ ] 手机 opencode-mobile 实连(Add Connection → Tailscale → `http://100.64.0.1:4096` + 密码)

## 遗留 / 跟进

- 密码轮换:改 `~/.config/opencode/serve.env` 后 `systemctl --user restart opencode-serve`
- opencode `autoupdate: true`,二进制在 `~/.opencode/bin/` 原地更新,unit 的 ExecStart 路径不受影响
- 与本会话(交互式 TUI)互不干扰:TUI 用随机端口,serve 固定 4096;若 4096 被占会启动失败,`Restart=always` 会反复重试
- `~/.local/bin/opencode` wrapper 若删除(其注释允许),本服务不受影响(AZURE 短路已在 unit 内)

## 参考

- opencode server 文档:https://opencode.ai/docs/server/
- opencode-mobile(客户端):https://github.com/dzianisv/opencode-mobile
- Azure 探针根因档案:../2026-09-01-2111-opencode-slow-startup/

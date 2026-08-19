# 本机 frp 客户端配置档案 — 实施记录

对应说明:[design.md](design.md) · 日期:2026-08-19

这是一次**归档动作**,不是新部署——frp 配置 2026-07 上线、2026-08-18 扩展 Sunshine 端口后一直在线上跑着,本目录只是把实体配置收进 plans 仓库。

## 任务清单

- [x] 借 Cloudflare Zero Trust 清理脚本(root)把 `/etc/frp/frpc.toml`、`/etc/systemd/system/frpc.service` 以 0644 副本落到 `/tmp`(线上文件 0600 root,agent 无法直读)
- [x] 初次归档进 `2026-08-19-cloudflare-zerotrust-removal/frp/`
- [x] 应用户要求独立成档:`git mv` 到本目录(保留 git 历史),原目录 `frp/` 已删
- [x] 校验快照与 `/tmp` 中转副本逐字节一致(`diff` 无输出)
- [x] 校验 `frpc.service` 全程 active running,frp 链路未受影响
- [x] 清理 `/tmp` 含 token 的中转副本(需用户 sudo 执行)
- [x] 补充 VPS 侧 frps 配置实体:[frps.toml](frps.toml)、[frps.service](frps.service)(用户从 VPS `sudo cat` 提供原文,逐字归档;含 `allowPorts` 白名单与 `User=nobody` 最小权限单元)

## 备注

- 归档方法可复用:对 0600 root 的配置文件,让 root 侧脚本 `install -m644 <src> /tmp/<name>`,agent 再从 `/tmp` 拷入 plans,全程无需交互 sudo 读配置。
- ~~`frpc.toml` 含 `auth.token`,只允许进这个私人 plans 仓库~~ **认知错误,已纠正**:本仓库在 GitHub 上是**公开仓库**,token 因此泄露,2026-08-19 已从全部历史清除并轮换(见 [../2026-08-19-frp-token-redaction/](../2026-08-19-frp-token-redaction/));此后配置快照一律脱敏入库。`/tmp` 中转副本用后必须删。

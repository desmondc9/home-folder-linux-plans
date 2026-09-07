# Implementation — LibreChat @ Bandwagon VPS

对应 spec.md。进度直接记在本文件。

- [x] T1:plans 目录 + spec.md/implementation.md(2026-09-07)
- [x] T2:GitHub repo `desmondc9/librechat-deployment`(private)创建(2026-09-07)
- [x] T3:Cloudflare 建 `librechat` A(`790aee9b…`)+ AAAA(`f1107228…`)灰云记录(2026-09-07)
- [x] T4:3 个 issue(部署跟踪 / SSO 接入 / RAG follow-up)
- [x] T5:openclaw 配置:chatCompletions 开 + 微信 channel 关(备份 `openclaw.json.bak-20260907-librechat`;重启后 `/v1/models` = openclaw/default+main,chat 往返 `"ok"` 验证通过;坑:token 存 secret store 只写,经 sqlite 只读取出)
- [x] T6:clone LibreChat v0.8.7 到 `~/repos/LibreChat`(2026-09-03 发布的 rc2 不用)
- [x] T7:`.env`(600,22 行)+ `librechat.yaml` + `override`(坑:upstream compose 默认镜像 `:latest`=rc2 → pin `librechat:v0.8.7`;新版需 `JWT_REFRESH_SECRET`)
- [x] T8:栈起:api+mongo+meili(坑:bind 目录首次被 daemon 建为 root 属主 → 全部 chown 1001:1001;RAG/vectordb/admin-panel 不启动)
- [x] T9:ufw `172.28.0.0/24→18789/tcp`;nginx vhost;certbot LE(证书 2026-09-07→12-06,自动续期);https v4+v6 均 200,80→443 301
- [ ] T10:端点验证:openclaw 已通(容器内直连 18789 实测);5 家 key 落位后 `/v1/models` 定稿模型清单
- [ ] T11:用户注册 → `ALLOW_REGISTRATION=false` → 重启
- [x] T12:deployment repo `dc7a593` 推送(README runbook / .env.example / ADR×3 / CONTEXT.md / vhost;密钥扫描通过);plans 仓库提交见本文件
- [ ] T13:验收清单逐项过(spec.md §验收标准)

## 备注

- key 文件:`~/librechat-keys.env`(0600,5 把 key;gateway token 从 openclaw.json 自取)
- compose 网段固定 172.28.0.0/24(override ipam),ufw 规则依赖此值
- LibreChat 官方坑:endpoint 块不完整会被**静默丢弃**(无日志),验收靠选择器可见性

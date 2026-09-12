# OpenClaw 经 tailnet 暴露(自签路线受阻 → ACME DNS-01 真证书 + tailnet-only)

- 日期:2026-09-06 22:20
- 环境:Kubuntu 26.04 + Wayland 笔记本(yaoshi15pro)(100.64.0.1;客户端 Android)
- 类型:本机服务配置 + 网络暴露面变更(无 repo 代码变更,无 PR)
- 状态:已上线并验证(HTTPS 200 + LE 证书链 + 本机 CLI + MCP 复测)

## 背景

目标:手机(tailnet 内 OnePlus-15 / iPhone-11)随时随地 full-access 访问本机
openclaw gateway。Android 首次配对硬性要求 real TLS endpoint(wss://),
raw tailnet IP 的 ws:// 不支持。

## 调研结论(grilling 两轮决策前的实测)

| 路线 | 结论 |
|---|---|
| `gateway.tailscale.mode=serve`(openclaw 原生集成) | **不可用**:tailscaled 报 501 Not Implemented。根因:控制面是自建 headscale(`https://bandwagon.signal-align.com`,MagicDNSSuffix=tailnet.internal,MagicDNSEnabled=false),LE 证书签发仅官方 ts.net 支持 → funnel 同理不可用 |
| `gateway.tls.*`(openclaw 原生 TLS 终结) | 可用:enabled/autoGenerate/certPath/keyPath,自签走 TOFU |
| DNS | signal-align.com 托管在 Cloudflare,本机 `~/.cloudflare/tokens.jsonc` 有可用 token(顺手 664→600) |
| `customBindHost` 语义 | 绑具体 IPv4 时自动保留 127.0.0.1 同端口监听 → 本机 CLI 不断 |

事故记录:先试 serve 时网关崩溃循环(每次启动 tailscale serve 失败即退出),
已回滚恢复。教训:mode=serve 在 headscale 环境是毒药,勿再开。

## 用户决策(Round 1/2)

- Q1 暴露模式:serve(后因 501 改道)/ **最终 A2:真域名证书 ACME DNS-01**
- Q2 绑定:**tailnet-only**(bind=custom → 100.64.0.1;关闭 LAN 0.0.0.0)
- Q3 ACL:不收紧(纯个人 tailnet)

## 实施

### 1. DNS(Cloudflare API,zone 3b564a8b…)

- A 记录 `openclaw.signal-align.com → 100.64.0.1`,proxied=false(grey),
  id 545a52abb9128af544c49a0334ffb0ae
- 公网 DNS 指向 CGNAT 地址:互联网不可路由,仅 tailnet 成员可达,无暴露面

### 2. 证书(acme.sh,~/.acme.sh/)

- 安装 acme.sh,默认 CA Let's Encrypt
- `--issue --dns dns_cf -d openclaw.signal-align.com`(CF_Token + CF_Zone_ID,
  token 会存入 ~/.acme.sh/account.conf,用户可读,正常行为)
- `--install-cert` → `~/.openclaw/tls/openclaw.signal-align.com.{cer,key}`(目录 700),
  reloadcmd = `systemctl --user restart openclaw-gateway.service`
- 续期:cron 已注册,到期 2026-12-05,续期后自动重启网关

### 3. 网关配置

```
gateway.tls.enabled=true + certPath/keyPath(上述路径)
gateway.bind=custom, gateway.customBindHost=100.64.0.1
gateway.publicOrigin=https://openclaw.signal-align.com:18789
```

## 验证

- 监听面:100.64.0.1:18789(TLS)+ 127.0.0.1:18789(本机明文),LAN 已关
- `https://openclaw.signal-align.com:18789/` → 200,证书 CN 匹配、LE 签发
- 明文 http 打 TLS 端口 → 拒绝
- 本机 CLI 推理(zhipu/glm-5.3)+ 4 MCP probe 全部正常

## Android 配对步骤(待用户执行)

1. OnePlus-15 连 tailscale + 装 OpenClaw app
2. 本机 `openclaw qr` 出 full-access 配对码(勿外传),app 扫码;
   或手动填 `wss://openclaw.signal-align.com:18789`(Secure/TLS)
3. 本机 `openclaw devices approve <requestId>`

## 回滚

- 网络面回 bind=lan:`openclaw config set gateway.bind lan` + 重启
- 撤证书链路:删 CF A 记录(上述 id)+ `acme.sh --remove -d openclaw.signal-align.com`
- gateway.tls.enabled=false 后网关回明文监听(需同时改回 bind)

# 自建 DERP 兜底中继(derp.signal-align.com)

日期:2026-08-19 · 状态:已完成

## 背景与目标

bandwagon VPS 上的 headscale(0.29.3)之前只有**内嵌 DERP**(region 999 "bwg",STUN UDP 3478,`derp.urls: []` 已移除公共 DERP 地图——iPad 曾漫游到国内 4G 不可达的 tok 区域)。内嵌 DERP 与 headscale 同进程:headscale 重启/崩溃时中继一起死。

目标:加一个**独立进程的 derper** 作为兜底中继,域名 `derp.signal-align.com`,放在 nginx 后面,TLS 用 certbot + nginx 获取(与 headscale 现有方式一致)。

## 方案

```
客户端 ──TLS 443──▶ nginx (derp.signal-align.com, LE 证书)
                        │ proxy_pass https://127.0.0.1:8443 (Upgrade 头, SNI 透传, 3600s 超时)
                        ▼
              derper v1.102.2 (systemd 独立服务, derper 用户)
              - DERP HTTPS @*:8443   (ufw 默认 deny,外部不可达,仅 nginx 本地回源)
              - STUN @*:3479/udp     (ufw 放行;3478 已被 headscale 内嵌 DERP 占用)
              - --verify-clients     (经本机 tailscaled.sock(0666)校验,仅 tailnet 成员可用)
              - -c /var/lib/derper/derper.key  (节点身份私钥,持久化)
```

- **两个 DERP 区域共存**:998(独立,"bwg-derp")+ 999(内嵌,"bwg"),同机房同延迟,客户端自动选;兜底的是 **headscale 进程故障** 场景,不是机房级冗余(整台 VPS 失联时走 frp 路径)。
- **证书**:certbot --nginx 签发;derper 用 `-certmode=manual -certdir=/var/lib/derper/certs`,deploy hook 在续期时复制 `fullchain.pem→<域名>.crt`、`privkey.pem→<域名>.key` 并重启 derper。
- **DNS**:Cloudflare 灰色云(DNS only),A→104.194.83.82,AAAA→2607:8700:5500:7bd3::2。橙色代理会挡 STUN 3479/udp,不可开。
- **headscale 注册**:`derp.paths: ["/etc/headscale/derp-standalone.yaml"]` 定义 region 998(DERPPort 443, STUNPort 3479)。

## 关键坑(实施中实际踩到)

1. **nginx `ipv6only=on` 只能在一个 server block 出现**:headscale 的 vhost 已声明 `listen [::]:443 ssl ipv6only=on;`,derp 的 vhost 再写就 `duplicate listen options`,nginx -t 直接失败。第二处写 `listen [::]:443 ssl;` 即可。
2. **derper v1.102 非 root 运行必须显式 `-c`**:不指定时非 root 直接 fatal `-c <config path> not specified`(root 才默认 `/var/lib/derper/derper.key`)。该文件是节点身份私钥,自动生成(0600)。
3. **STUN 绑定跟随 `-a` 的 IP**:`-a=127.0.0.1:8443` 会让 STUN 也只绑回环,外部不可达。`-a=:8443`(通配)→ STUN 绑 `[::]:3479` 双栈;8443/TCP 靠 ufw 默认 deny 挡住(不放行即可)。
4. **derper manual certmode 强制 SNI**:无 SNI 的 TLS 握手直接 alert 80 拒绝 → nginx 回源 502。必须 `proxy_ssl_server_name on; proxy_ssl_name derp.signal-align.com;`(默认会发 `127.0.0.1` 当 SNI,也不对)。

## 验收结果

- `curl https://derp.signal-align.com/` → derper 官方页面(经 nginx)✓
- `curl -H "Upgrade: derp" .../derp` → 101 Switching Protocols ✓
- 笔记本 `tailscale netcheck`:bwg 138.7ms + bwg-derp 138.7ms 双区域在线 ✓(bwg-derp 的延迟数字本身即证明 STUN 3479 双栈可达)
- `certbot renew --dry-run` 通过 ✓

## 相关档案

- 整体 tailnet 设计:`~/plans/2026-08-18-sunshine-moonlight-tailnet/`
- 出口节点 + sing-box 分流:`~/plans/2026-08-18-tailnet-exit-singbox/`

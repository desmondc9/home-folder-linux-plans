# sing-box REALITY 全中断:Ubuntu 26.04 升级移除 resolved 的 D-Bus 接口

- **日期**: 2026-11-14(故障窗口 12:45–13:00 CST)
- **机器**: brave-goose-1(95.169.0.65 / 2607:8700:5500:7bd3::2)
- **类型**: 运维故障诊断 + 修复(无项目代码变更)
- **状态**: 已修复并双端验证通过

> Test Plan 说明:本次为运维排障,不涉及任何项目仓库的代码/配置文件变更(改的是本机
> `/etc/sing-box/config.json`),按规范可省略测试计划;验证过程与结果记录在「验证」一节。

## 背景与架构

brave-goose-1 从 Ubuntu 24.04 升级到 26.04,12:45 重启。重启后 sing-box 服务本身
active + enabled、`sing-box check` 通过,但**代理完全不可用**。

本机 REALITY 链路(升级前后无变化,均完好):

```
客户端 → nginx:443(SNI 分流,/etc/nginx/stream-enabled/sing-box-443.conf)
        ├─ SNI=www.cloudflare.com → 127.0.0.1:24444(剥 proxy_protocol)→ sing-box REALITY @ 127.0.0.1:24443
        └─ 其他 SNI(default)      → 127.0.0.1:14443(本机网站/DERP 等)
```

- systemd unit: `/etc/systemd/system/sing-box.service`
- 二进制: `/usr/local/lib/sing-box/1.14.4/sing-box`(v1.14.4,CGO disabled)
- 配置: `/etc/sing-box/config.json`(root 600,升级前 `.dns` 段为 null)

## 现象

journal 中每秒数条错误洪峰(12:52 密集出现,实为客户端疯狂重连):

```
ERROR inbound/vless[vless-reality]: process connection from 127.0.0.1:xxxxx:
TLS handshake: REALITY: failed to dial dest: lookup www.cloudflare.com:
(exchange4: Name "org.freedesktop.resolve1" does not exist | exchange6: Name "org.freedesktop.resolve1" does not exist)
```

## 根因分析(证据链)

1. **主机 DNS 正常**:`getent hosts www.cloudflare.com` 成功、`curl https://www.cloudflare.com` HTTP 200,
   `/etc/resolv.conf` → 127.0.0.53 stub,systemd-resolved active。
2. **D-Bus 接口消失**:`NameHasOwner org.freedesktop.resolve1` 返回 false;新版 systemd 的
   systemd-resolved 只暴露 varlink(`io.systemd.Resolve`)+ monitor socket,**不再注册传统
   D-Bus 名称**。`/usr/share/dbus-1/system-services/org.freedesktop.resolve1.service` 和
   dbus alias 软链虽在,但永远不会被激活成功。→ 26.04 升级引入的变化。
3. **sing-box 已知缺陷**:`local` 型 DNS(无显式 dns 段时的隐式默认)在 Linux 上默认
   `prefer_go: false` → 走 systemd-resolved 的 D-Bus 通道;它靠 resolv.conf 注释文本判定
   "systemd-resolved 管理",选中 D-Bus 后**失败不回退**到读 resolv.conf。
   Upstream: [SagerNet/sing-box#4637](https://github.com/SagerNet/sing-box/issues/4637)
   (修复仅存在于 fork 分支,截至 2026-11 未合并发布)。
4. **REALITY 对每个连接都拨 dest**:读 v1.14.4 源码确认 —— metacubex/utls v1.8.7 的
   `RealityServer()` 在读 ClientHello、做认证**之前**就无条件 `DialContext(ctx, Type, Dest)`,
   因为即使客户端认证成功,伪造握手响应也需要真实 dest 的握手字节做模板。
   → 解析挂了 = **所有连接(含认证客户端)在 TLS 握手阶段全灭**,自 12:45 重启起完全中断。
5. **误导性证据排查**:443 端口上来自中国电信 IPv6 的 established 连接实为 DERP/网站流量
   (SNI 非 cloudflare,被 nginx 分流到 default 后端),并非 sing-box 存活证明。

### 影响范围

- REALITY 握手全灭 → 代理完全中断(并非只有"探测回落失效");
- VLESS 服务端解析客户端请求域名同样依赖这套 DNS → 即使握手修好,代理流量也解析不了;
- 防探测能力失效:探测者拿到连接重置而非真实 Cloudflare 页面,有暴露特征被墙的风险。
- 防火墙(ufw/nftables)经升级后完好,443 放行规则齐全,与本故障无关。

## 修复

给 sing-box 显式配置 `local` DNS 并强制 Go 原生解析(绕过 D-Bus,直接读
`/etc/resolv.conf` → 127.0.0.53 stub → resolved,该路径已验证可用):

```json
"dns": { "servers": [ { "type": "local", "prefer_go": true } ] }
```

实施(2026-11-14 13:00 前后执行,一次通过):

```bash
sudo jq '.dns = {"servers":[{"type":"local","prefer_go":true}]}' /etc/sing-box/config.json > /tmp/opencode/config-fixed.json && \
sudo /usr/local/lib/sing-box/1.14.4/sing-box check -c /tmp/opencode/config-fixed.json && \
sudo cp --preserve=all /etc/sing-box/config.json /etc/sing-box/config.json.bak-upgrade2604 && \
sudo cp /tmp/opencode/config-fixed.json /etc/sing-box/config.json && \
sudo systemctl restart sing-box
```

(`prefer_go` 文档:https://sing-box.sagernet.org/configuration/dns/server/local/ ;
同款 workaround 见 fscarmen/sing-box#280)

## 验证

| 验证项 | 结果 |
|---|---|
| 模拟 GFW 探针 `curl --connect-to www.cloudflare.com:443:95.169.0.65:443 https://www.cloudflare.com/` | 修复前:TLS 连接被掐断(unexpected eof);修复后:真实 Cloudflare 证书(Let's Encrypt 签发)+ **HTTP 200,0.14s** |
| Android v2rayNG 客户端 | ✅ 恢复 |
| Windows 11 sing-box 客户端 | ✅ 恢复 |
| 服务状态 | active,`sing-box check` 通过 |

## 遗留事项

- [ ] 观察几天后删除备份 `/etc/sing-box/config.json.bak-upgrade2604` 和 `/tmp/opencode/config-fixed.json`
- [ ] 关注 sing-box 新版本是否包含 #4637 的回退修复;`prefer_go: true` 保留无副作用,无需回滚
- [ ] (可选)审计本机其他依赖 `org.freedesktop.resolve1` D-Bus 的服务 —— 26.04 之后它们会以同样方式静默挂掉(走 127.0.0.53 stub 的不受影响)

## 参考

- Upstream issue: https://github.com/SagerNet/sing-box/issues/4637(D-Bus 无 owner 时不回退)
- prefer_go workaround: https://github.com/fscarmen/sing-box/issues/280
- 源码: sing-box v1.14.4 `common/tls/reality_server.go`(DialContext 闭包)、
  `common/dialer/dialer.go`(ResolveDialer)、metacubex/utls v1.8.7 `reality.go`
  (`RealityServer()` 无条件先拨 dest)
- 本地相关条目: `~/plans/2026-08-18-2224-tailnet-exit-singbox/`

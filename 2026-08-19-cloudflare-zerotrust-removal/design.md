# 移除 Cloudflare Zero Trust 残留 + 归档 frp 配置

日期:2026-08-19 · 状态:**全部完成**(本机 + CF 云端均已验证无残留) · 实施记录:[implementation.md](implementation.md)

## 背景与目标

- 2026-07 已把本机对外 SSH 从 Cloudflare Tunnel 迁到自建 frp(bandwagon VPS);2026-08-18 串流方案又加了自建 tailnet 主链路(见 [../2026-08-18-sunshine-moonlight-tailnet/](../2026-08-18-sunshine-moonlight-tailnet/))。CF Zero Trust 对本机已无任何价值,且 WARP 在中国大陆不可用(GFW 封 WARP/MASQUE 协议本身,2026-07 实测确认)。
- **目标 1**:彻底移除本机 Cloudflare Zero Trust 组件——cloudflared 包、手动安装的 systemd 单元、apt 源/keyring、软链、ssh config 条目,以及 cloudflare-warp 的 rc 残留配置。
- **目标 2**:把本机 frp 配置归档进本仓库——已独立成档,见 [../2026-08-19-frp-config-archive/](../2026-08-19-frp-config-archive/)。

## 范围

**In scope:**
- 本机 `cloudflared`(deb 2026.8.2)与 `cloudflare-warp`(2026.4.1390.0,rc 态)purge
- `/etc/systemd/system/cloudflared.service` + `cloudflared-update.{service,timer}` 删除
- apt 源 `cloudflared.list` / `cloudflare-client.list` 与两个 keyring 删除
- `/usr/local/bin/cloudflared` 软链删除
- `~/.ssh/config` 中 `Host yaoshi15pro.signal-align.com`(ProxyCommand cloudflared)条目删除
- frp 配置快照归档 → 独立目录 [../2026-08-19-frp-config-archive/](../2026-08-19-frp-config-archive/)(最初落在本目录 `frp/`,同日移出)

**Out of scope:**
- Cloudflare dashboard 侧资源(tunnel、Access app、7 月遗留的 CIDR route / enrollment policy / `*.cfargotunnel.com` CNAME)——需用户登录控制台手动删,见「遗留」
- VPS 侧 `frps` 不动
- tailnet / sing-box 分流体系不受影响

## 现状分析(移除前快照)

- `dpkg -l`:`cloudflared 2026.8.2 (ii)`;`cloudflare-warp 2026.4.1390.0 (rc)` —— 7 月已删 warp 二进制但配置残留至今。
- systemd:`/etc/systemd/system/cloudflared.service`(disabled/inactive,token 直写在 ExecStart 里,属远端托管 tunnel)+ `cloudflared-update.{service,timer}`。**这三个单元由 `cloudflared service install` 写入,不属于 deb 包内容(`dpkg -L` 不含),`apt purge` 不会删,必须手动 rm。**
- apt 源:`/etc/apt/sources.list.d/cloudflared.list`(pkg.cloudflare.com)、`cloudflare-client.list`(pkg.cloudflareclient.com, noble),keyring 两个在 `/usr/share/keyrings/`。
- `/usr/local/bin/cloudflared` → `/usr/bin/cloudflared` 的便利软链(包purge后会悬空)。
- `~/.ssh/config`:`yaoshi15pro.signal-align.com` 条目依赖 `cloudflared access ssh`,卸载即失效,同步删除。
- `/etc/cloudflared`、`~/.cloudflared` 已不存在(7 月迁移时已清)。

## frp 现状(归档对象)

`frpc.service`(enabled, running)→ `/usr/local/bin/frpc -c /etc/frp/frpc.toml`;对端 frps 在 bandwagon VPS(`bandwagon.signal-align.com:7000`,token auth)。**实体文件与详细说明已移至 [../2026-08-19-frp-config-archive/](../2026-08-19-frp-config-archive/)**,此处只留速览。

代理一览:

| name | type | local | remote | 用途 |
|---|---|---|---|---|
| kubuntu-ssh | tcp | 127.0.0.1:22 | :6000 | 外网 SSH:`ssh -p 6000 desmond@laptop.signal-align.com`(A 记录灰云指 VPS,仅作 DNS) |
| sunshine-tcp-47984 / 47989 / 48010 | tcp | 同端口 | 同端口 | Moonlight:API / RTSP / 控制 |
| sunshine-udp-47998 / 47999 / 48000 / 48002 / 48010 | udp | 同端口 | 同端口 | Moonlight:视频 / 控制 / 音频 / 麦克风 |

transport 调优(相对默认值):`tcpMuxKeepaliveInterval = 10`(yamux 心跳,默认 30s)、`dialServerKeepAlive = 30`(底层 TCP SO_KEEPALIVE,默认 7200s 太长)。

注意:`frpc.toml` 含 `auth.token`,本仓库为私人档案库,入库符合惯例;**不要**把本目录内容复制到任何公开仓库。

## 移除方案

脚本 `/tmp/remove-cloudflare-zerotrust.sh`,由用户以 `! sudo bash ...` 交互执行(sudo 走人脸解锁,agent 无法直接提权):

1. `systemctl disable --now` cloudflared.service + cloudflared-update.timer(实际本已 disabled,防御性执行)
2. 删除 3 个 `/etc/systemd/system/cloudflared*` 单元文件
3. `apt purge -y cloudflared cloudflare-warp`(purge 顺带清掉 warp 的 rc 残留)
4. 删除 2 个 apt 源 + 2 个 keyring
5. 删除 `/usr/local/bin/cloudflared` 软链
6. `systemctl daemon-reload`
7. 顺带把 `/etc/frp/frpc.toml`、`/etc/systemd/system/frpc.service` 以 0644 副本落到 `/tmp`(绕开 0600 root 权限,供归档)

脚本末尾自检:二进制/包/单元三者均不存在才输出 `ALL DONE`。

## 验收标准

- `command -v cloudflared` 为空;`dpkg -l cloudflared cloudflare-warp` 无 `ii`/`rc` 行;`/etc/systemd/system/cloudflared*` 不存在;无相关进程;`/etc/apt/sources.list.d/` 无 cloudflare 条目;`/usr/share/keyrings/cloudflare*` 不存在。
- `frpc.service` 保持 active running(frp 链路不受影响)。
- `frp/` 快照与线上 `/etc/frp/frpc.toml`、`/etc/systemd/system/frpc.service` 内容一致。

## 风险与缓解

- **误删 frp 或无关包** → 脚本只碰 cloudflare 命名的对象,purge 显式列出两个包名;frp 仅读不写。
- **dashboard 残留 tunnel 的安全面** → token 随单元文件删除而从本机消失;云端 tunnel 记录转为 inactive,无入向连接能力,风险可忽略,列为手动清理项。
- **ssh config 删条目后无法回退** → 该入口 7 月起已由 frp(`ssh -p 6000 desmond@laptop.signal-align.com`)完全替代,无回退需求。

## 云端清理(2026-08-19 已全部完成并验证)

- [x] Networks → Tunnels:删除 `yaoshi15pro` tunnel(用户 dashboard 手动,已确认)
- [x] Workers & Pages:删除 Edgetunnel Worker 及 `edgetunnel.signal-align.com` 自定义域(用户 dashboard 手动;DNS 记录随绑定解除自动删除,API 复查 CLEAN)
- [x] DNS 终审:CF API 全量复查 `signal-align.com`,`edgetunnel` / `yaoshi15pro` / `cfargotunnel` 零匹配
- 7 月遗留的 CIDR route / enrollment policy / Access app:随 Zero Trust 整体弃用而失去意义,客户端侧已无任何组件,不再单独核对

## DNS 审计结果(2026-08-19,dns-token 走 CF API)

`signal-align.com` 全区记录逐条核对:

| 记录 | 归属 | 结论 |
|---|---|---|
| `bandwagon` / `derp` / `laptop` / apex 的 A+AAAA → VPS | frps / headscale+DERP / frp SSH 入口 / apex | 全部在用,保留 |
| MX ×3 + SPF + `cf2024-1._domainkey` DKIM | Cloudflare Email Routing | 现役功能,保留 |
| `edgetunnel` AAAA `100::` 橙云(2026-06-02 建) | Edgetunnel(Workers 版 VLESS)占位记录,Workers Custom Domain 托管 | 用户确认弃用 → 删除,但需走 dashboard(见上) |
| ~~`yaoshi15pro` / `*.cfargotunnel.com` CNAME~~ | 7 月隧道 | **已不存在,无需清理** |

另两个 zone(`centific.dev`、`uthant.studio`)均为工作域名(SendGrid/Passbolt/Azure 记录),无任何 CF Tunnel/Zero Trust 残留。

## 参考

- [../2026-08-18-sunshine-moonlight-tailnet/](../2026-08-18-sunshine-moonlight-tailnet/) —— frp 作为串流备份链路的部署记录
- [../2026-08-19-frp-config-archive/](../2026-08-19-frp-config-archive/) —— frp 配置实体快照与运维说明
- 记忆:`moonlight-sunshine-tailscale-setup`(frp 端口矩阵、VPS 侧 frps 配置)

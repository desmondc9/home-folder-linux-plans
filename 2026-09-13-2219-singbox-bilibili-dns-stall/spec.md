# Windows 宿主 sing-box 下 bilibili 偶发卡顿:根因是裸 UDP DNS 间歇性卡死

日期:2026-09-13 · 状态:已修复并验证(6 分钟浸泡 0 卡顿) · 流程:systematic-debugging skill(四阶段,先根因后修复)

- 环境:WSL2 Ubuntu 26.04 @ Windows 11 物理机 DESKTOP-J7NBNU4(mirrored networking);sing-box 1.13.19 以 Windows 服务运行于 `C:\Users\Desmond\Apps\sing-box\`(TUN + mixed:10809);Tailscale MagicDNS(CorpDNS)开启;网络环境为中国大陆家宽 + VPS(104.194.83.82)VLESS-Reality 出口

## 背景与症状

Windows 宿主机 sing-box 服务运行期间,**偶尔**访问 bilibili 看视频非常卡顿。用户怀疑分流路由出问题。

## 范围

**In:** 定位卡顿根因并修复(宿主机 sing-box 服务配置)。
**Out:** Tailscale MagicDNS 双重代理的彻底消除(登记为后续变量);`udp/443 reject` 规则(QUIC 封禁,与本次卡顿无关,属既定策略)。

## 根因(证据链)

**结论:不是分流规则问题——bilibili 流量一直正确 direct。卡顿 = DNS 间歇性卡死。**

1. **路由正常**:clash API(`/connections`)实时连接显示 api.bilibili.com / bilivideo.com / hdslb.com 全部 `chains=direct`(rule_set=[geosite-cn geoip-cn] => direct)。
2. **卡顿本体**:日志中反复出现 `dns: exchange failed for {api.bilibili.com, api.vc.bilibili.com, i2.hdslb.com} IN {A,AAAA}: context deadline exceeded (10.0s)`;每次事故窗口内并发的多条 alidns 交换集体卡 7-10 秒后**同一时刻**恢复(如 20:28:21-31 一例:8 条并发查询,7.4-9.8s 完成、2 条 10s 超时)。视频缓冲停等 7-10 秒 = "非常卡顿"。
3. **为什么 bilibili 最受伤**:`i2.hdslb.com` 等 CDN 域名 **TTL 只有 10 秒**(日志可见 `i2.hdslb.com. 10 IN ...`),播放页每几秒就要重解析,是全部直连域名中 DNS 查询频率最高的;任何 DNS 抖动都被 bilibili 放大成可见卡顿。
4. **放大器(为什么是"偶尔"、且成串卡)**:Tailscale MagicDNS(`CorpDNS: true`)接管系统 DNS,把**所有**应用查询先汇入 tailscaled,再以并发竞速(同时打 223.5.5.5 + 1.1.1.1)灌进 sing-box TUN——一次用户查询被放大 ×4-8(日志:tun 内 DNS 流量 tailscaled.exe 7809 条 vs chrome.exe 717 条)。突发并发触发上游丢包/限流,集体卡死。
5. **对照组(Phase 2)**:同一配置里走 DoH/TCP 的 `cfdoh`(经 VPS)从未出现 10s 卡死——只有 `type: udp` 的 alidns 传输中招。裸 UDP:53 无重传保证、对突发并发和丢包最脆弱。
6. 次要噪音:`router: process DNS packet: unpack request: bad question name: dns: bad rdata`(数百条)全部来自 tailscaled 的长生命周期 UDP 会话——双劫持(tailscale→sing-box)下的畸形包被丢弃,本身无害,但印证了 DNS 双重代理的脆弱架构。

### 故障链全貌

```
Chrome/应用 → Windows stub → tailscaled (MagicDNS, 竞速放大 ×4-8)
  → sing-box TUN hijack-dns → sing-box DNS 模块
  → alidns: 裸 UDP:53 → 223.5.5.5   ← 间歇性丢包/限流,7-10s 卡死或 10s 超时
                                    ← (对照) cfdoh DoH/TCP 经 VPS: 从不卡死
bilibili CDN 域名 TTL≈10s 高频重解析 → 每次 DNS 黑洞 = 7-10s 视频缓冲停等
```

## 修复(单变量)

`config.json` 的 `alidns` DNS server 传输层:`type: udp` → **`type: https`**(即 `https://223.5.5.5/dns-query`)。阿里 DoH 走 TCP,抗丢包、无 UDP QPS 丢包问题,仍经 geoip-cn 直连、不影响 CDN 就近调度。前置验证:证书含 `IP Address:223.5.5.5` SAN(openssl 实测);RFC 8484 查询 HTTP 200。备份:`config.json.bak-20260913-alidns-doh`。

## 验收标准与结果

| 标准 | 结果 |
|---|---|
| 重启后 DNS 交换无 >2s 卡顿、无 deadline 超时 | 6 分钟浸泡 636/636 全部 <500ms,0 失败(含 115 条 bilibili 域名) |
| bilibili 域名解析延迟恢复毫秒级 | ~12ms(完整 CNAME 链) |
| 分流无回归 | bilibili 页面 200(约 90ms);实时连接仍 direct |
| 代理路径无回归 | `curl -x 127.0.0.1:10809 https://api.ipify.org` → 104.194.83.82 |

## 风险与后续

- **若复发,下一个变量**:关闭 Tailscale 的 DNS 接管(`tailscale set --accept-dns=false`),消除双重代理与 ×4-8 放大——代价是失去 MagicDNS 域名解析,需用户确认后再动。
- 备选加固:alidns 之外加 DNSPod(119.29.29.29)DoH 作第二上游;或 sing-box 增加独立 DNS 监听供 tailscale 上游指向。
- `~/docs/network-access-china.md` 已同步一笔(该文档描述此 sing-box 服务)。

## 参考

- 日志:`C:\Users\Desmond\Apps\sing-box\logs\sing-box-service*.err.log`(info 级,ANSI 色码需 `sed -E 's/\x1b\[[0-9;]*m//g'` 清洗)
- Notebook 同步:[sing-box-分流网关/06-深坑清单](~/Notebook/sing-box-分流网关/06-深坑清单.md)、[04-DNS-分流与防污染](~/Notebook/sing-box-分流网关/04-DNS-分流与防污染.md)

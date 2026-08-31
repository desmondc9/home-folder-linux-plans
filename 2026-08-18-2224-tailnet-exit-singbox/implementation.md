# Tailnet 双 Exit Node + sing-box 分流 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本任务涉及大量 sudo/远程 VPS 操作，子代理无法交互认证，必须 inline 执行。

**Goal:** 笔记本(Kubuntu 26.04,国内)和 VPS(bandwagon,美国)都成为 tailnet Exit Node;笔记本上用 sing-box 对出口流量做"国内直连/国外代理/自定义规则"分流，全 tailnet 设备入网即翻墙。

**Architecture:** iPad/Android 通过 tailnet(WireGuard P2P,IPv6 直连)把互联网流量发给笔记本 Exit Node;笔记本上 tailscaled 转发给本机 sing-box(TPROXY 入站),sing-box 按 rule-set(geosite-cn/geoip-cn/geosite-gfw + 用户自定义 local rule-set)分流:国内 DIRECT 走电信家宽，其余 PROXY 走 VPS 的 VLESS+Reality+vision。VPS 上另装 tailscaled 做无分流的兜底出口。headscale(已有)负责批准两个 exit node 的路由。

**Tech Stack:** sing-box v1.13.19 / tailscale 1.102.2 / headscale 0.29.3 / nftables(inet family) / systemd-resolved

**Spec:** 本文件即 spec(需求来自 2026-08-18 会话讨论:1. 国内直连 2. 国外+被墙走代理 3. 用户可自定义规则;V2rayN 退役但暂留作回退)。

## Global Constraints

- **不破坏现有服务**:tailscaled(headscale 已接入)、frpc(Sunshine 转发+SSH)、Sunshine 串流、VPS 上 nginx/headscale/frps。每个 Task 结束必须验证这些仍正常。
- **回退要求**:任何一步出问题,sing-box 必须能一键停用(`sudo systemctl stop sing-box sing-box-tproxy`),网络恢复原状。V2rayN 保持运行直到 Task 9 全部验证通过。
- **防回环**:sing-box 自身出站(routing_mark 255)、tailscaled 自身流量(mark 0x80000)、headscale/VPS 直连流量(104.194.83.82)、私网与 tailnet 地址段,一律不进 TPROXY。
- **sudo 需用户执行**:本会话无免密 sudo。所有标记 `[用户执行]` 的步骤由用户在输入框用 `! <cmd>` 运行并贴回输出;VPS 上标记 `[VPS执行]`。
- **节点参数(已从 v2rayN 配置提取,直接可用)**: server=104.194.83.82 port=45575 uuid=<VLESS-UUID> flow=xtls-rprx-vision sni=www.ebay.com pbk=<REALITY-PUBLIC-KEY> fp=chrome,short_id 为空。
- **下载全部走代理**:`export https_proxy=http://127.0.0.1:10808 http_proxy=http://127.0.0.1:10808`(V2rayN 退役前有效)。

---

### Task 1: 安装 sing-box

**Files:**
- Create: `/tmp/sing-box.deb`(临时)

- [x] **Step 1: 下载 v1.13.19 deb 包** ✅ 2026-08-18

```bash
export https_proxy=http://127.0.0.1:10808 http_proxy=http://127.0.0.1:10808
curl -fSL -o /tmp/sing-box.deb "https://github.com/SagerNet/sing-box/releases/download/v1.13.19/sing-box_1.13.19_linux_amd64.deb"
ls -lh /tmp/sing-box.deb   # 期望 ~10MB
```

- [x] **Step 2: 安装并确认版本** `[用户执行]` ✅ 1.13.19 已装,deb 创建 sing-box 用户/服务

- [x] **Step 3: 备份 deb 默认配置** ✅ `/etc/sing-box/config.json.bak`

---

### Task 2: sing-box 主配置 + 自定义规则文件

**Files:**
- Create: `~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/config.json`(发布到 `/etc/sing-box/config.json`)
- Create: `~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/rules/custom-direct.json`(发布到 `/etc/sing-box/rules/`)
- Create: `~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/rules/custom-proxy.json`(同上)

**Interfaces:**
- Produces: sing-box 监听 TPROXY `:7896`、HTTP/SOCKS mixed `:10809`;outbound tag `proxy`/`direct`;rule-set tag `geosite-cn`/`geoip-cn`/`geosite-gfw`/`custom-direct`/`custom-proxy`。后续 Task 的 nftables 和 DNS 均依赖这些端口与 tag。

- [ ] **Step 1: 写主配置**(本步骤由 AI 直接写文件)

`~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/config.json`:

```json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "tag": "alidns", "type": "udp", "server": "223.5.5.5" },
      { "tag": "cfdoh", "type": "https", "server": "1.1.1.1", "detour": "proxy" }
    ],
    "rules": [
      { "rule_set": ["custom-direct"], "server": "alidns" },
      { "rule_set": ["custom-proxy"], "server": "cfdoh" },
      { "rule_set": ["geosite-cn"], "server": "alidns" },
      { "rule_set": ["geosite-gfw"], "server": "cfdoh" }
    ],
    "final": "cfdoh",
    "strategy": "prefer_ipv4",
    "independent_cache": true
  },
  "inbounds": [
    { "type": "tproxy", "tag": "tproxy-in", "listen": "::", "listen_port": 7896 },
    { "type": "mixed", "tag": "mixed-in", "listen": "0.0.0.0", "listen_port": 10809 }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "104.194.83.82",
      "server_port": 45575,
      "uuid": "<VLESS-UUID>",
      "flow": "xtls-rprx-vision",
      "routing_mark": 255,
      "tls": {
        "enabled": true,
        "server_name": "www.ebay.com",
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": { "enabled": true, "public_key": "<REALITY-PUBLIC-KEY>", "short_id": "" }
      }
    },
    { "type": "direct", "tag": "direct", "routing_mark": 255 }
  ],
  "route": {
    "rules": [
      { "action": "sniff" },
      { "protocol": "dns", "action": "hijack-dns" },
      { "ip_is_private": true, "outbound": "direct" },
      { "rule_set": ["custom-direct"], "outbound": "direct" },
      { "rule_set": ["custom-proxy"], "outbound": "proxy" },
      { "rule_set": ["geosite-cn", "geoip-cn"], "outbound": "direct" },
      { "rule_set": ["geosite-gfw"], "outbound": "proxy" }
    ],
    "rule_set": [
      { "tag": "geosite-cn", "type": "remote", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs",
        "download_detour": "proxy", "update_interval": "7d" },
      { "tag": "geoip-cn", "type": "remote", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
        "download_detour": "proxy", "update_interval": "7d" },
      { "tag": "geosite-gfw", "type": "remote", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-gfw.srs",
        "download_detour": "proxy", "update_interval": "7d" },
      { "tag": "custom-direct", "type": "local", "format": "source", "path": "/etc/sing-box/rules/custom-direct.json" },
      { "tag": "custom-proxy", "type": "local", "format": "source", "path": "/etc/sing-box/rules/custom-proxy.json" }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  }
}
```

要点:`routing_mark: 255`(0xff)使 sing-box 自己的出站包被 nftables 豁免,防回环;`final: proxy` = 未命中规则的默认出国(与 Shadowrocket GEOIP-CN-direct 逻辑一致);`custom-*` 排在 geosite 之前,用户规则优先。

- [ ] **Step 2: 写自定义规则文件**

`~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/rules/custom-direct.json`(国内直连例外,示例已含一条注释示例;空规则合法):

```json
{
  "version": 2,
  "rules": [
    {
      "domain": [],
      "domain_suffix": [],
      "domain_keyword": [],
      "ip_cidr": []
    }
  ]
}
```

`~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/rules/custom-proxy.json`(强制走代理例外):

```json
{
  "version": 2,
  "rules": [
    {
      "domain": [],
      "domain_suffix": [],
      "domain_keyword": [],
      "ip_cidr": []
    }
  ]
}
```

用法(写进 Task 10 文档):往数组里加 `"openai.com"`(domain_suffix)或 `"1.2.3.0/24"`(ip_cidr),然后 `sudo systemctl restart sing-box`。

- [x] **Step 3: 发布配置并校验** `[用户执行]` ✅ CONFIG-OK(补了 sing-box 1.12+ 必填的 `route.default_domain_resolver: alidns`,详见 spec.md 风险表)

---

### Task 3: 启动 sing-box 并用 mixed 代理口验证分流逻辑

- [x] **Step 1: 启动并看日志** `[用户执行]` ✅ rule-set 修正:geosite-gfw.srs 404 → 改用 geosite-greatfire.srs;三个 rule-set 均 updated

- [x] **Step 2: 国外流量验证(应显示 VPS 美国 IP)** ✅ api.ipify.org → 104.194.83.82;google 200

- [x] **Step 3: 国内流量验证(应显示家宽 IP,非 VPS)** ✅ myip.ipip.net → 114.92.157.156 上海电信;baidu 200

---

### Task 4: nftables TPROXY + 路由策略(本机全量接管)

**Files:**
- Create: `~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/tproxy.nft`(发布到 `/etc/sing-box/tproxy.nft`)
- Create: `~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/sing-box-tproxy.service`(发布到 `/etc/systemd/system/`)
- Create: `~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/99-exit-node.conf`(发布到 `/etc/sysctl.d/`)

**Interfaces:**
- Consumes: Task 2 的 TPROXY 端口 7896、routing_mark 255。
- Produces: fwmark 1 + 策略路由表 100;tailscale0 入向互联网流量与本机 OUTPUT 流量全部进入 sing-box。

- [ ] **Step 1: 写 nftables 规则文件**

`~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/tproxy.nft`:

```nft
table inet singbox {
    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        meta mark 0xff return
        meta mark 0x80000 return
        ip daddr 104.194.83.82 return
        ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16, 224.0.0.0/4 } return
        ip6 daddr { ::1, fc00::/7, fe80::/10, fd7a:115c:a1e0::/48 } return
        iifname "tailscale0" meta l4proto { tcp, udp } tproxy to :7896 meta mark set 1 accept
    }
    chain output {
        type route hook output priority mangle; policy accept;
        meta mark 0xff return
        meta mark 0x80000 return
        ip daddr 104.194.83.82 return
        ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16, 224.0.0.0/4 } return
        ip6 daddr { ::1, fc00::/7, fe80::/10, fd7a:115c:a1e0::/48 } return
        meta l4proto { tcp, udp } meta mark set 1
    }
}
```

豁免顺序:sing-box 自身(0xff)→ tailscaled 自身(0x80000)→ VPS 直连(frp/headscale/DERP/WG)→ 私网/tailnet/组播 → 其余全部 TPROXY。prerouting 只拦 tailscale0 入向(Exit Node 客户端流量),不拦 LAN 入向。

- [ ] **Step 2: 写 systemd 单元(规则加载/清理 + 策略路由)**

`~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/sing-box-tproxy.service`:

```ini
[Unit]
Description=sing-box TPROXY nftables rules and policy routing
Before=sing-box.service
After=network-pre.target tailscaled.service
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/sing-box/tproxy.nft
ExecStart=/usr/sbin/ip rule add fwmark 1 lookup 100
ExecStart=/usr/sbin/ip route add local 0.0.0.0/0 dev lo table 100
ExecStart=-/usr/sbin/ip -6 rule add fwmark 1 lookup 100
ExecStart=-/usr/sbin/ip -6 route add local ::/0 dev lo table 100
ExecStop=/usr/sbin/nft delete table inet singbox
ExecStop=-/usr/sbin/ip rule del fwmark 1 lookup 100
ExecStop=-/usr/sbin/ip route del local 0.0.0.0/0 dev lo table 100
ExecStop=-/usr/sbin/ip -6 rule del fwmark 1 lookup 100
ExecStop=-/usr/sbin/ip -6 route del local ::/0 dev lo table 100

[Install]
WantedBy=multi-user.target
```

`~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/99-exit-node.conf`:

```sysctl
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
```

(当前运行时已是 1,此文件做持久化。)

- [x] **Step 3: 发布并启动** `[用户执行]` ✅ 首次部署失败:本机流量 OUTPUT 打 mark→策略路由回环到 lo→prerouting 只匹配 tailscale0 无人接住→无限路由循环黑洞。修复:prerouting 增加 `iifname "lo"` tproxy 规则(2026-08-19)

Expected: nft 表存在;sing-box 正常重启。

- [x] **Step 4: 本机全量接管验证** ✅ 2026-08-19 00:05 修复后全过:沙盒(ubuntu 24.04/26.04 podman, --cap-add=NET_ADMIN)先行验证 → 主机 dig@223.5.5.5 劫持正常、baidu 200、ipip.net 家宽、google 200、ipify=VPS、anthropic 404(可达)

- [x] **Step 5: 回归验证现有服务** ✅ sunshine/frpc/tailscaled/sing-box/sing-box-tproxy 全 active,tailnet P2P 3ms

---

### Task 5: 笔记本 DNS 切到 sing-box 分流解析

**Files:**
- Create: `~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/singbox-dns.conf`(发布到 `/etc/systemd/resolved.conf.d/`)

- [ ] **Step 1: 写 resolved 配置**

`~/plans/2026-08-18-2224-tailnet-exit-singbox/sing-box-deploy/singbox-dns.conf`:

```ini
[Resolve]
DNS=223.5.5.5
Domains=~.
```

原理:resolved 把查询发给 223.5.5.5 → 被 OUTPUT 链 TPROXY 劫进 sing-box → `hijack-dns` → sing-box DNS 模块按 rule-set 分流(国内 alidns 直连解析 / 国外 DoH 经 VPS 解析),兼顾速度与防污染。

- [x] **Step 2: 发布并重启 resolved** `[用户执行]` ✅(踩坑:resolved.conf.d 目录需先建;DHCP 链路 DNS 抢优先 → nmcli ignore-auto-dns yes)

- [x] **Step 3: DNS 验证** ✅ taobao→国内CDN,google→142.251.x 真实无投毒

---

### Task 6: 笔记本成为 Exit Node 并在 headscale 批准

- [x] **Step 1: 开启 exit node 通告** `[用户执行]` ✅ AdvertiseRoutes 已设(tailscale debug prefs 确认)

- [x] **Step 2: 在 VPS 的 headscale 批准路由** `[VPS执行]` ✅ 0.29 CLI 变更:`headscale routes` 已移除 → `headscale nodes approve-routes --identifier 1 --routes 0.0.0.0/0,::/0`

- [x] **Step 3: 确认客户端可见** ✅ `tailscale exit-node list` 可见

---

### Task 7: VPS 成为第二个 Exit Node `[VPS执行]`

- [x] **Step 1: 生成新预授权 key** ✅(脚本内联完成)

- [x] **Step 2: VPS 装 tailscale + 转发 + 入网 + 通告出口** ✅ 节点 4 brave-goose-1 100.64.0.4;另修 ufw DEFAULT_FORWARD_POLICY=ACCEPT(默认 DROP 会拦出口转发流量)

- [x] **Step 3: headscale 批准 VPS 的 exit 路由** ✅ `approve-routes --identifier 4`

- [x] **Step 4: 笔记本侧确认两个出口都可见** ✅ `offers exit node`

---

### Task 8: 端到端验证(iPad + Android)

- [x] **Step 1: Exit Node = 笔记本(分流模式)** ⚠️ 部分通过

iPad(4G,Tailscale 开,Shadowrocket 关): Exit Node 选 `desmond-yaoshi15proseriesgm5ix0a`。

- [x] `myip.ipip.net` → ✅ 114.92.157.156 上海电信(国内直连)
- [x] `google.com` → ✅ 正常访问(经 VPS,v6 路径)
- [x] `api.ipify.org` → ✅ 104.194.83.82(经 VPS,v6 路径)
- [ ] `ipv4.google.com` → ❌ **已知问题**:tailnet 客户端经笔记本出口的 v4-only 国外域名不可达(v6 全通;TPROXY/REDIRECT 在 TUN 接口跨栈查找丢包,详见 spec.md 已知限制)

- [x] **Step 2: Exit Node = VPS(全局美国模式)** ✅ `brave-goose-1` 出口正常

- [x] **Step 3: Exit Node = None** ✅ 恢复正常

- [x] **Step 4: Android 重复 Step 1** ⚠️ 同上:v6 正常,v4-only 国外域名同样受限

- [ ] **Step 5: 自定义规则演练** 待后续验证(规则通道已配置,未实测)

---

### Task 9: 收尾与文档

- [ ] **Step 1: V2rayN 处置**

确认 sing-box 全链路稳定后:退出 V2rayN 并取消其自启动(系统设置→自启动,或 `~/.config/autostart/`)。注意:此后本机 10808 消失,需要代理下载时改用 sing-box 的 10809(或本机 OUTPUT 已被接管,通常不再需要显式代理)。**VPS 上的 xray 服务端不动。**

- [ ] **Step 2: 更新 memory**

更新 `~/.claude/projects/-home-desmond/memory/moonlight-sunshine-tailscale-setup.md`:补充双 exit node、sing-box 配置位置(`/etc/sing-box/`)、自定义规则用法、TPROXY 单元名、回退命令。

- [ ] **Step 3: 使用文档(写进 memory 或单独说明)**

自定义规则:编辑 `/etc/sing-box/rules/custom-direct.json`(强制直连)或 `custom-proxy.json`(强制代理),数组元素支持 `domain`(精确)、`domain_suffix`、`domain_keyword`、`ip_cidr`;改完 `sudo systemctl restart sing-box`。

---

## 回退总开关

```
! sudo systemctl disable --now sing-box sing-box-tproxy && sudo tailscale set --advertise-exit-node=false && sudo rm /etc/systemd/resolved.conf.d/singbox-dns.conf && sudo systemctl restart systemd-resolved
```

VPS 侧:`sudo tailscale down`(必要时 headscale 里禁用路由)。所有改动可逆,不动 frp/headscale/sunshine。

# Windows 11 宿主机(YAOSHI15PRO)加入 headscale tailnet + 控制面新域名挂载 设计文档

日期: 2026-09-22 · 状态: 已完成 · 实施记录: [implementation.md](implementation.md)
- 环境: WSL2 Ubuntu 26.04 @ Windows 11 Pro 笔记本 YAOSHI15PRO(原 Kubuntu 节点所在机,现已换 Windows);headscale v0.29.3 @ Bandwagon VPS brave-goose-1(104.194.83.82);Windows 侧经 WSL interop 操作

## 背景与目标

YAOSHI15PRO 原为 Kubuntu(node 1, 100.64.0.1, Sunshine 出口节点, 2026-09-11 起离线),现已是 Windows 11 + WSL2 mirrored 工作环境,**未装 Tailscale**。需要把这台 Windows 宿主机加入现有 headscale tailnet,控制面使用规范域名 `headscale.signal-align.com`。

该域名当前**不存在**(CF 权威 NXDOMAIN):无 DNS 记录、无证书、nginx 无对应 server_name、headscale `server_url` 仍指旧域名。因此任务分两半:VPS 侧给现有 headscale 实例挂新域名(不动存量节点),Windows 侧装客户端入网。

目标:
1. `https://headscale.signal-align.com` 可达并服务现有 headscale(存量 9 节点零影响)
2. YAOSHI15PRO 以 `yaoshi15pro-win` 入网,通告 Exit Node 并获 headscale 批准
3. WSL mirrored 环境(podman 工作流)与 sing-box TUN 分流零回归

## 范围

**In scope:**
- CF DNS: `headscale.signal-align.com` A → 104.194.83.82(**灰云**,沿用既有原则)
- VPS nginx: 新增 vhost 服务新域名(独立证书,不扩旧证书 SAN),certbot HTTP-01
- headscale: 删除失联旧 node 1;签发一次性 preauth key;批准新节点 exit node 路由
- Windows: winget 安装 Tailscale(MSI, 一次 UAC),`tailscale up` 指向新域名
- 验证: 新域名健康检查、节点在线、WSL 经 mirrored 访问 tailnet、podman 回归

**Out of scope:**
- `server_url` 切换(用户决策:保持旧域名 `https://bandwagon.signal-align.com`,旧 vhost/证书原样保留)
- 存量 8 节点的控制面迁移(继续走 bandwagon vhost)
- iPad/手机端任何改动
- Windows 侧 sing-box 配置改动(豁免清单已含 tailnet 网段,实测确认零改动)
- 富途/自定义规则等 sing-box 语义(已就绪)

## 现状(2026-09-22 实测)

| 事实 | 值 | 来源 |
|---|---|---|
| 本机身份 | Windows 11 Pro(build 26200)YAOSHI15PRO + WSL2 mirrored/dnsTunneling/firewall=true | interop 实测 |
| 宿主 Tailscale | **未安装**(无服务、无 Program Files 目录) | interop 实测 |
| 宿主 sing-box | v1.14.1,NSSM 服务(`D:\Desmond\Apps\sing-box\config.json`),运行中 | interop 实测 |
| sing-box 豁免 | `route_exclude_address` 已含 `100.64.0.0/10`、`fd7a:115c:a1e0::/48`、`104.194.83.82/32`、`2607:8700:5500:7bd3::2/128`;`strict_route: false`;hijack-dns 存在 | jq 实测 |
| headscale | v0.29.3 active,listen 127.0.0.1:8080 ← nginx;`server_url: https://bandwagon.signal-align.com`;MagicDNS false;DERP 固定文件(bwg-derp 独立 + 内嵌,auto_update off) | SSH 实测 |
| nginx vhost | 文件名 `headscale` 但 server_name 仅 `bandwagon.signal-align.com`,证书 LE 有效期至 2026-11-16 | SSH 实测 |
| 节点清单 | id 1–9 = 100.64.0.1–.9(1=旧 Kubuntu 本机失联,4=VPS 在线,其余离线);用户 desmond(id 1) | SSH 实测 |
| 新域名 DNS | `headscale.signal-align.com` CF 权威 NXDOMAIN(zone NS ingrid/roman.ns.cloudflare.com);bandwagon 仅 A 无 AAAA | Resolve-DnsName 实测 |
| CF 凭据 | 本机 `~/.cloudflare/credentials.jsonc` 的 `dns-token` active,对 signal-align.com 有 `#dns_records:edit` | API verify 实测 |
| VPS 访问 | `ssh desmond@bandwagon.signal-align.com` 免密;`sudo -n` NOPASSWD | 实测 |

## 方案设计

### 总体流程

```
[WSL] CF API 建 A 记录(灰云) ──▶ [VPS] 新 vhost(headscale-new)+ certbot ──▶ /health 绿
                                                                      │
[WSL interop] winget 装 Tailscale(UAC 一次)                           │
                                                                      ▼
[VPS] 删 node 1 + 签 preauth key(不入库) ──▶ [Windows] tailscale up --login-server=https://headscale.signal-align.com
                                                --hostname=yaoshi15pro-win --accept-dns=false
                                                --advertise-exit-node --authkey=<KEY>
                                                                      │
[VPS] headscale nodes approve-routes --identifier <N> --routes 0.0.0.0/0,::/0
                                                                      ▼
                                                        验收(status/netcheck/WSL/podman)
```

### 关键设计决策

1. **server_url 不动**(用户决策):旧 bandwagon vhost + 证书原样保留,存量节点继续走旧域名;新域名只是并行入口。headscale 0.29 不校验 Host 头,preauth 流程无重定向依赖 server_url,实测 /health + 注册验证。
2. **独立新证书,不扩旧证书 SAN**:certbot 给 `headscale.signal-align.com` 单独签证书 + 独立 vhost 文件,完全不改存量 vhost 与其证书 → 存量 9 节点零风险、零重载;回退 = 删新 vhost 一个文件。
3. **Exit Node 通告**(用户决策):`--advertise-exit-node` + headscale 批准。已知容量限制:Windows tailscaled 用户态转发天花板 ~8Mbps(2026-09-12 Task 5c 实测教训),作为"轻量浏览可用"的第三出口存在;`ExitNodeID` 保持空(不自选出口,防循环路由)。
4. **`--accept-dns=false`**:宿主 DNS 已由 sing-box TUN hijack-dns + WSL dnsTunneling 管理;headscale 侧 MagicDNS 也是关的。显式 false 防止 tailscale 抢 DNS 造成互相劫持。
5. **删除旧 node 1 后再注册**:释放 100.64.0.1 与主机名混淆;新节点实际 IP 以注册结果为准(headscale 0.29 分配策略决定,记录实测值)。
6. **sing-box 零改动**:豁免清单已覆盖 tailnet v4/v6 网段与 VPS 双栈,证明该配置母本出自 DESKTOP-J7NBNU4 同款(共存范式已被 2026-09-12 全量验收)。
7. **机密红线**:preauth key 只经 shell 变量/WSL↔Windows 进程参数传递,不写入任何 git 跟踪文件(档案中一律 `__PREAUTH_KEY_REDACTED__` 占位)。

### 风险与缓解

| 风险 | 等级 | 缓解 |
|---|---|---|
| mirrored WSL × Tailscale 适配器镜像 | 中 | DESKTOP-J7NBNU4 同构实测共存正常(2026-09-12 Task 3 Step 5);验收含 WSL localhost/podman/DNS 回归;异常回退 = `tailscale down` |
| winget 装 MSI 需要提权 | 低 | 一次 UAC(用户在场点击),沿用 2026-09-12 `Start-Process -Verb RunAs` 模式 |
| DNS 传播延迟导致 certbot/注册失败 | 低 | CF 灰云记录秒级生效;创建后经 1.1.1.1 + 223.5.5.5 双验证再进下一步 |
| certbot HTTP-01 被墙/失败 | 低 | 同机 4 张 LE 证书续期正常(v4 443/80 直连);失败可 `--preferred-challenges dns` 兜底 |
| server_url 与新域名不一致引发隐性引用 | 低 | preauth 流程无浏览器重定向;DERP 走固定文件;验收含注册后 map 轮询观察 |

## 验收标准

1. `curl https://headscale.signal-align.com/health` → OK(VPS 侧与本机双验);旧域名 /health 同样 OK(存量兼容)
2. `tailscale status`:`yaoshi15pro-win` 在线,可见 VPS 节点(100.64.0.4)等 peers
3. `tailscale netcheck`:UDP true,bwg-derp 延迟与既有基线(~131ms)同量级
4. WSL 回归:localhost 互通、`podman ps`、外网解析正常;`ssh desmond@100.64.0.4`(经宿主 tailnet)可达
5. Exit Node 生效:headscale 侧 `approve-routes` 成功;VPS 节点 `tailscale exit-node list` 出现 `yaoshi15pro-win.tailnet.internal`
6. 回退开关就位:`tailscale down` / `sc stop Tailscale` / 删 vhost 文件,均不影响存量节点
7. 本档案归档 + README 索引补行;gitleaks 扫描无泄漏(preauth key 不入库)

## 性能与容量

- 本任务为网络配置变更,无代码/DB/查询变更,Step G 触发项:无(出口通告为既有 headscale 能力,无新查询路径)。
- 容量已知项登记:Windows exit node 用户态转发 ~8Mbps 天花板(引用 2026-09-12-0021 Task 5c),iPad/iPhone 端使用时知晓;Linux/VPS 出口不受影响。

## 参考

- 存量拓扑与节点清单: [../2026-08-19-1302-sunshine-moonlight-tailnet/](../2026-08-19-1302-sunshine-moonlight-tailnet/spec.md)
- Windows 侧 Tailscale + sing-box TUN + mirrored WSL 共存先例: [../2026-09-12-0021-windows11-exit-node-singbox/](../2026-09-12-0021-windows11-exit-node-singbox/spec.md)(DESKTOP-J7NBNU4,node 7)
- 独立 derper 与四坑: [../2026-08-19-1430-headscale-custom-derp/](../2026-08-19-1430-headscale-custom-derp/spec.md)
- 服务部署地图(headscale/derp 属 VPS 手工管理): ~/Repos/desmondc9-signal-align/signal-align-umbrella/README.md

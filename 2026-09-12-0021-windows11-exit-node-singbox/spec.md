# Windows 11 物理机成为第三个 Exit Node(TUN 版 sing-box 分流) 设计文档

日期:2026-09-12 · 状态:已批准,实施中 · 实施计划:[implementation.md](implementation.md)
- 环境:Windows 11 物理机(DESKTOP-J7NBNU4)(经 WSL2 mirrored interop 操作)

## 背景与目标

现有 tailnet 双出口(笔记本 TPROXY 分流 + VPS 全局兜底,见 [../2026-08-18-2224-tailnet-exit-singbox/](../2026-08-18-2224-tailnet-exit-singbox/spec.md))运行稳定。新的主力机是 **Windows 11 物理机**(desktop-j7nbnu4,WSL2 Ubuntu 工作环境所在宿主机),常年开机,比会合盖休眠的笔记本更适合做日常出口。

目标:**Windows 11 物理机成为第三个 Exit Node,与笔记本/VPS 并存**,具备同款 sing-box 分流能力(国内直连/国外走 VLESS-Reality/自定义规则/DNS 防污染),tailnet 客户端(iPad/Android/iPhone)在出口下拉多一个选择,笔记本侧零改动。

## 范围

**In scope:**

- Windows 11 物理机上 sing-box v1.13.19(Windows 版)**TUN 模式**透明分流(笔记本的 TPROXY/nftables 在 Windows 不可用)
- Windows 主机 `--advertise-exit-node` + headscale 批准(node identifier 7)
- 配置从笔记本档案逐行平移,VLESS 节点参数从本机 v2rayN 提取(不入库)
- v2rayN 验证期并存 → 稳定后退役(复用笔记本剧本)

**Out of scope:**

- 笔记本/VPS 侧任何改动(三出口并存,谁开机用谁)
- Windows 侧已有客户端的翻墙配置(iPad/Android 入网自动获得能力)
- dockur Win11 VM(100.64.0.5)——NAT 内无公网 v6,不适合做分流出口,维持现状

## 现状(2026-09-12 实测,来自 WSL interop 摸底)

| 事实 | 值 | 影响 |
|---|---|---|
| 本机身份 | Windows 11 物理机 + WSL2 Ubuntu 26.04(AI 经 WSL 执行,Windows 侧可 interop) | 多数步骤可代跑,提权步骤需 UAC |
| WSL 网络模式 | **mirrored**(`.wslconfig networkingMode=mirrored`,podman 工作流刚需) | **不能退回 NAT**;sing-box TUN 全量接管宿主路由时 WSL 行为需实测 |
| Tailscale | 已装已登录 headscale(`ControlURL: bandwagon.signal-align.com`),node id **7**,100.64.0.7,在线;有两个 tailscaled.exe 进程(疑似残留,待清理) | 接入步骤已天然完成,只剩 advertise + approve |
| 公网 IPv6 | `240e:389:a35b:3e10::1cb`(电信家宽 Native v6) | P2P 打洞条件与笔记本同级 |
| DERP | netcheck:bwg-derp 131.4ms,UDP true | 双 region 正常 |
| v2rayN + xray | 正在运行,xray 监听 **127.0.0.1:10808**(非 10809) | sing-box mixed 10809 **无冲突**;退役照搬笔记本 Task 9 剧本 |
| sing-box | 未安装 | 全新部署 |
| VPS 访问 | WSL `ssh desmond@100.64.0.4` 免密,`sudo -n headscale` NOPASSWD | approve-routes 由 AI 从 WSL 代跑 |
| Windows sudo | 无 sudo.exe | 提权 = 用户开一个 UAC 管理员 PowerShell |

## 方案设计

### 总体架构(与笔记本对照)

```
iPad/Android ──WireGuard P2P(IPv6)──> Windows tailscaled(100.64.0.7)
     │                                       │ 转发流量按 Windows 路由表
     │                                       ▼
     │                            sing-box TUN(auto_route 接管默认路由)
     │                                       │ 按 rule-set 判定
     │                    ┌──────────────────┴─────────────────┐
     │               国内 DIRECT                        国外 PROXY
     │                    ▼                                    ▼
     │              电信家宽直连                    VLESS+Reality → VPS:45575
     └──tailnet 内部流量(100.64/10)──豁免,不进 sing-box──> 各节点服务
```

### Linux → Windows 组件映射(笔记本 → 本机)

| 笔记本(Linux) | Windows 11 等价 | 说明 |
|---|---|---|
| nftables TPROXY `:7896` + 策略路由表 100 | `tun` inbound(`auto_route: true`) | Windows 唯一透明接管方式 |
| `routing_mark: 255` + nft mark 豁免防回环 | `auto_detect_interface: true`(出站绑定物理网卡)+ `route_exclude_address`(VPS 双栈 IP 永不进 TUN) | 防回环机制完全不同,双保险 |
| nft 目的地址豁免清单 | tun `route_exclude_address` 同一份清单平移(私网/100.64/10/fd7a::/48/VPS v4+v6) | 另加 `process_name` 规则直连 tailscaled.exe |
| systemd `sing-box.service` | Windows 服务(WinSW 包装;1.13.19 无 `service` 子命令,实测) | 开机自启 + 崩溃自动重启 |
| `sing-box-tproxy.service`(规则加载) | 不需要——auto_route 随 TUN 生命周期自动增删路由 | 回退更干净:停服务即恢复 |
| systemd-resolved→223.5.5.5 被 TPROXY 劫持 | TUN 成为首选 DNS 接口 + `hijack-dns` 规则 | alidns/cfdoh 分流逻辑逐行不变 |
| `99-exit-node.conf` sysctl(ip_forward) | 不需要——tailscaled 自管 Windows 转发/NAT | |
| `--advertise-exit-node` + headscale approve-routes | 命令完全相同,identifier=7 | |
| VLESS outbound / rule-set / custom-* 规则 / DNS 模块 | config 逐行平移 | 差异仅:去 `routing_mark`、`block`→`action: reject`(1.12+ 修复,见 [../2026-09-03-1824-singbox-block-outbound-fix/](../2026-09-03-1824-singbox-block-outbound-fix/spec.md))、custom 规则路径改 Windows |

### 关键设计决策

1. **TUN 而非 TPROXY(别无选择)**:笔记本当初"TPROXY 优先于 TUN"的决策(避免与 tailscaled netfilter 交互)在 Windows 不成立——Windows 无 netfilter/TPROXY,TUN 是唯一路径。风险面反而不同:Windows 上 tailscaled 不用 netfilter,双方各自独立 wintun 适配器。
2. **`strict_route: false` 起步**:strict_route 叠加 WFP 防火墙规则,与 tailscaled 的 WFP 过滤器有互相干扰的社区报告;且 mirrored WSL 与 WFP 的交互是未知数。先松后紧,稳定后再评估收紧。
3. **豁免三层防护**:① `route_exclude_address`(VPS v4+v6、私网、tailnet 段)使关键流量根本不进 TUN;② `process_name: [tailscaled.exe, tailscale-ipn.exe] → direct` 兜住 tailscaled 进程级流量;③ `ip_is_private → direct`。对应笔记本的"防回环三道豁免"。
4. **mixed 10809 保留**:WSL podman 的 `http_proxy=127.0.0.1:10809` 约定不变(v2rayN 实占 10808,无冲突);mirrored 模式下 WSL 与宿主共享 localhost。
5. **v2rayN 渐进退役**:验证期并存(xray 出站到 VPS:45575 被目的豁免,不进 TUN,零干扰);全部验收后取消自启,复用笔记本 Task 9 剧本。
6. **出口并存不互选**:Windows 作为出口服务端期间**不选择任何 exit node**(prefs 当前 `ExitNodeID: ""`,保持),否则循环路由。
7. **节点参数不入库**:VLESS uuid / Reality pbk 用占位符,真实值部署时从本机 v2rayN 配置提取直接写入 `C:\ProgramData\sing-box\config.json`(红线惯例)。

### 风险与缓解

| 风险 | 等级 | 缓解 |
|---|---|---|
| **mirrored WSL × sing-box TUN 交互**(宿主默认路由被接管后 WSL 出网/解析行为未知;WSL 可能试图镜像新 TUN 适配器) | 高 | 分阶段验证(先装不启 → 启动后立即验证 WSL podman/网络);出问题即 `sc stop sing-box`(路由随 TUN 消失,秒级回退);最坏预案:WSL 加 `[experimental] hostAddressLoopback`/忽略镜像或退 NAT(会破坏 podman 流程,需重新评估) |
| strict_route/WFP 与 tailscaled 互扰 | 中 | 初始 false;收紧前逐项回归 tailscale status/netcheck |
| 两个 tailscaled.exe 进程(摸底发现,疑似更新残留) | 中 | 实施首步重启 Windows 清理;若复现查服务与孤儿进程 |
| Windows 侧 DNS 泄漏(TUN 未成为首选解析路径时) | 中 | 验收含 nslookup 走向检查;strict_route 收紧可彻底封 |
| v2rayN 用户习惯回退 | 低 | 退役前保留;10808 端口 sing-box 不占 |
| WSL 流量也被分流(gvisor 栈开销) | 低 | 属预期特性;镜像拉取走国内 mirror 直连不受影响 |

## 验收标准

1. **Windows 本机分流**:`myip.ipip.net` → 电信家宽 IP;`api.ipify.org` → 104.194.83.82;google.com 可访问;QUIC 站点正常(action: reject 生效无超时)
2. **WSL 回归**:mirrored 网络正常(localhost 互通、podman pull、ssh 100.64.0.4)
3. **tailscale 回归**:status 在线,netcheck 双 region,与 iPad P2P v6 直连
4. **iPad(4G)Exit Node = desktop-j7nbnu4**:myip.ipip.net 家宽 IP;google 可访问且出口为 VPS;Moonlight 串流笔记本不受影响(tailnet 内部流量豁免)
5. **v2rayN 并存无干扰**:xray 10808 全程可用
6. **自定义规则演练**:custom-proxy.json 加测试域名 → 走代理,移除恢复
7. **回退验证**:停 sing-box 服务 → Windows/WSL/tailnet 秒级复原,无需手动清路由

## 参考

- 笔记本原版设计与实施(配置母本):[../2026-08-18-2224-tailnet-exit-singbox/](../2026-08-18-2224-tailnet-exit-singbox/spec.md)
- sing-box Windows 配置实体:[sing-box-deploy/config.windows.json](sing-box-deploy/config.windows.json)
- `block` 出站移除修复:[../2026-09-03-1824-singbox-block-outbound-fix/](../2026-09-03-1824-singbox-block-outbound-fix/spec.md)
- WSL mirrored 工作流(不可破坏的约束):[../2026-09-11-2120-podman-wsl-ubuntu-native/](../2026-09-11-2120-podman-wsl-ubuntu-native/spec.md)

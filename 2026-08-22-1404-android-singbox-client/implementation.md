# Android sing-box 客户端配置 — 实施记录

- 日期:2026-08-22
- 前置:`~/Notebook/sing-box-分流网关/` 知识库(本机配置详解)、redroid 容器(droidvm 管理)

## 阶段 1:环境与素材准备

1. `droidvm start` 拉起 redroid(Android 15,1272x2772,adb 127.0.0.1:5555)
2. 经本机 10809 代理下载 GitHub Releases v1.13.19:
   - `SFA-1.13.19-universal.apk`(redroid 为 x86_64 宿主,universal 含原生 x86_64 lib;真机用 arm64-v8a)
   - `sing-box-1.13.19-android-amd64.tar.gz`(裸 core,redroid 原生)
   - `sing-box-1.13.19-android-arm64.tar.gz`(真机用)
   - 静态工具:`curl-amd64`(moparisthebest/static-curl)、`busybox 1.35 x86_64-musl`、`cacert.pem`
3. 源码考古:sing-box 主仓 v1.13.19 tag 的 `experimental/libbox/`、`daemon/`、`docs/clients/android/`;SFA 源码仓库 sing-box-for-android 的 1.13.19 版本 bump commit `aed2b6ea`

## 阶段 2:配置编写

本机 `/etc/sing-box/config.json` 语义 1:1 移植,改动点:

- inbounds:替换 tproxy+mixed → 单个 tun(`address` 合并字段、mtu 9000、auto_route、strict_route、stack gvisor)
- outbounds:去掉 `routing_mark: 255`(本机 nftables 防回环专用)
- ruleset 本地两条改绝对路径(SFA 工作目录)
- 其余(DNS servers/rules/final/strategy、route 规则顺序、final=proxy、3 个远程 srs、QUIC block、default_domain_resolver)原样保留

本机 `sing-box check`(同为 1.13.19)校验结构通过;设备端 android-amd64 core `check` 通过(CORE_CHECK_OK)。

## 阶段 3:裸 core 验证(root + tun,确定性最高)

1. push 到 `/data/local/tmp/sb/`,测试配置加 `route_exclude_address: ["104.194.83.82/32","223.5.5.5/32","10.89.0.0/16"]`(core 自身出站防环 + 保 adb)
2. 启动:rule-set 3 个全部经 VLESS 下载成功;tun0 起来后 `ip rule` 显示 auto_route 表 2022 就位
3. 踩坑:第一次启动留下孤儿 tun0 导致 `TUNSETIFF: device or resource busy` → `ip link del tun0` 后重跑;setsid + `</dev/null` 后台化防 adb 会话回收
4. 测试脚本(设备 toybox 无 awk、grep 无 `{n,m}`):busybox nslookup 指定 8.8.8.8(查询进 tun 被 hijack→分流)+ `grep -E '^Address: [0-9]+\.' | tail -1 | cut -d' ' -f2` 取 IPv4 + curl `--resolve`
5. 结果:b1 api.ipify.org→104.194.83.82(VPS)、b2 myip.ipip.net→114.92.157.156(家宽)、b3 google 200、b4 taobao 200(61.170.76.149 CDN)、b5 github 200
6. override 双向:custom-proxy 加 ipip.net → myip.ipip.net 出口翻转成 VPS(log:`outbound/vless → 172.66.155.12:443`,DNS 走 cfdoh 602ms);custom-direct 加 ipify.org → `outbound/direct → 104.26.12.205:443`(DNS 走 alidns 9ms)。验后还原

## 阶段 4:SFA App 实测

1. 安装 universal APK;profile 经 `file:///data/data/io.nekohasekai.sfa/files/config.json` + `am start VIEW` intent 导入(SFA 导入时**真跑 core 校验**,ruleset 可读才放行)
2. 踩坑链:
   - scoped storage 挡 file:///sdcard 与 content://(两个 provider 都要求 SAF)→ 改用应用私有目录 file URI
   - `error_create_service`("Create service")是错误对话框标题,消息为空 → 用 `log.output` 文件 + trace 级日志定位:core 在 network 初始化后即死
   - **根因**:logcat `E VpnJni: Cannot allocate TUN: Bad file descriptor` — Android netd 打开 `/dev/tun`,redroid 缺该节点 → `mknod /dev/tun c 10 200`(与 /dev/net/tun 同 10,200)
   - **修好后 VPN 建立成功,但 adb 被 VPN 吞**(本地子网未豁免)→ `sudo podman exec redroid am force-stop io.nekohasekai.sfa` 恢复;测试 profile 加 `route_exclude_address: ["10.89.0.0/16"]`(Android 侧体现为 tun0 表 `throw 10.89.0.0/16`)
3. 最终 VPN 内验证:
   - b1 api.ipify.org → 104.194.83.82(VPS)✓;b2 myip.ipip.net → 114.92.157.156(家宽)✓;google/github → 200 经代理 ✓;taobao → 200 直连 CDN ✓
   - a:core.log 显示 myip.ipip.net 查询 5-10ms(阿里)、api.ipify.org 578ms(DoH 经 VPS);nslookup 走 tun 返回 baidu 国内 CDN / google 真实 v6
   - c:custom-proxy 加 ipip.net → 重启服务 → myip.ipip.net 出口翻转成 VPS(104.194.83.82 洛杉矶),对照组 ipify 不受影响 ✓;验后还原
   - 路由层面证据:`ip rule` 中 uidrange 0-99999 → lookup tun0(所有 App 无感知接管),tun0 表 `default dev tun0`

## 阶段 5:交付物

| 位置 | 内容 |
|------|------|
| `~/singbox-android/config.json` | 最终配置(真实机密,非 git 目录) |
| `~/singbox-android/rules/custom-{direct,proxy}.json` | 自定义 ruleset(与 /etc/sing-box/rules/ 同源) |
| `~/singbox-android/README-手机导入.md` | 手机导入/override/验证快照说明 |
| `~/plans/…/config.sanitized.json` | 脱敏快照(本档案,公开仓库) |

待办(需 sudo):复制到 `/etc/sing-box/android/` 与本机配置并排(root 归档,与线上机密同保护等级)。

## 阶段 6:真机验证

2026-08-22 用户实际 Android 手机(arm64-v8a SFA)导入验证成功 — DNS 分流/流量分流/override 行为与 redroid 实测一致。

## 复盘要点

- **文档站 ≠ 目标版本**:sing-box 官方文档展示 1.14+ 字段(dns_mode),1.13.19 会报 unknown field;以目标版本二进制 `check` 为准
- **SFA 相对路径基准** = `/storage/emulated/0/Android/data/io.nekohasekai.sfa/files/`(从导入报错信息中实测得出)
- **VpnJni EBADF** = `/dev/tun` 缺失,与 TUNSETIFF busy 是两个不同的坑
- redroid 无 VPN 本地子网豁免 → 测试必须显式 route_exclude_address,否则 adb 失联
- 静态 musl curl 在 Android 上不用 netd resolver(空 resolv.conf → "Could not resolve host"),测试需 nslookup+--resolve 组合

## 附录 v2: 2026-09-12 复启用手机 SFA(Windows 出口转发瓶颈 → 手机本地分流)

背景见 [../2026-09-12-0021-windows11-exit-node-singbox/implementation.md](../2026-09-12-0021-windows11-exit-node-singbox/implementation.md) Task 5c:tailscaled Windows 用户态转发天花板 ~8Mbps,手机经 Windows 出口国内图站不可用 → 手机改回本地 SFA 分流(国内 4G 直连/国外直连 VPS),Tailscale 不开 exit 仅访家。

本档案 config 的 v2 变更(config.sanitized-v2.json,脱敏快照;真值 profile 由当日会话生成):

1. 修 1.12+ 已移除的 `"outbound": "block"` → `"action": "reject"`(2026-09-03-1824 档案预告的欠账)
2. 富途 37 后缀**内联**进 route(`→ proxy`)与 dns(`→ cfdoh`)规则,置于 custom-proxy 之后——与笔记本/Windows 的 futu rule-set 语义一致但不再依赖额外文件(SFA 导入即校验,少一个 local rule-set 依赖)
3. 其余(tun gvisor/mtu 9000/DNS 分流/custom-* 路径)与 v1 完全一致;custom-*.json 沿用手机应用目录既有文件

导入:HTTP 经 tailnet 下发(`http://100.64.0.7:18080/config.json`,WSL mirrored 临时服务),SFA 从文件导入;结果见验证段(下)。

## 附录 v3: 2026-09-12 一体化(单 VPN 同时解决分流 + tailnet 访问)

用户指出 Android 单 VPN 限制:Tailscale app 与 SFA 互斥(v2 方案"保留 Tailscale 访家"不可行,与 iOS Shadowrocket 互斥同类)。解法:sing-box 1.12+ 内置 `tailscale` endpoint(文档确认支持 `control_url` 自定义协调服务器,headscale 兼容;1.13.19 实测 `sing-box check` 通过):

1. `endpoints[]`: type=tailscale, control_url=headscale, auth_key=headscale preauth key(90d reusable,真值只在下发配置中,不入库), hostname=oneplus-15-sfa, accept_routes=false
2. route 规则(置于 hijack-dns 后): `ip_cidr: [100.64.0.0/10, fd7a:115c:a1e0::/48, 100.100.100.100/32] → outbound: ts-ep`(注意 1.13.19 路由规则引用 endpoint 用 `outbound` 字段而非 `endpoint` 字段——后者 1.14 才有,踩坑记录)
3. DNS 增加 `type: tailscale` server(经 ts-ep 解析)+ `tailnet.internal → ts-dns` 规则(MagicDNS)
4. 效果:SFA 单 VPN = 分流上网(国内直连/国外 VLESS)+ 完整 tailnet(Moonlight/SSH 到 100.64.0.x);Tailscale app 退役(旧节点 oneplus-15 离线属预期)

## 附录 v3 续: 真机验证通过 + 工作原理沉淀 2026-09-12

**验收**:用户真机确认"运行正常"——分流上网(Moonlight/国外/国内)与 tailnet 访问并存于单 VPN。headscale 侧:`oneplus-15-sfa` = node id 8 = 100.64.0.8 online(旧 Tailscale app 节点 oneplus-15 离线属预期,App 退役)。临时 HTTP 下发服务(WSL mirrored :18080)已关闭。preauth key 仅首次注册用,节点状态持久化,90 天过期不影响在册节点。

**SFA 内嵌 tailscale 工作原理(知识沉淀)**:

1. sing-box 把 Tailscale 官方 Go 客户端库编译进进程(`with_tailscale` build tag)——进程内跑着一个"真·tailscaled",非官方 App、非协议模拟。
2. **控制面**:endpoint `control_url` → headscale,preauth key 注册、领取 100.64.0.x 身份、拉网络地图(含自建 bwg/bwg-derp DERP 表),与官方 App 同一套协议。
3. **数据面**(与官方 App 的关键差异):内嵌版**不开自己的 TUN**,WireGuard 会话完全用户态运行,在 sing-box 路由图里就是一个普通 outbound(与 proxy/direct 平级)。tailnet 网段(100.64.0.0/10 + fd7a:115c:a1e0::/48 + 100.100.100.100)由规则导向 `ts-ep`;UDP(Moonlight 串流)同路。
4. **防回环**:内嵌客户端自身的控制/对端 socket 经 VpnService protect 绕过 TUN 直走物理网卡(等价笔记本 TPROXY 的 mark 0x80000 豁免)。
5. **单 VPN 互斥因此消失**:全机仅 SFA 一个 VpnService 消费者,Tailscale 退化为它内部的一条路由分支;`type: tailscale` DNS server = 经内嵌客户端的 MagicDNS(`*.tailnet.internal` 可解析)。
6. endpoint 另有 `exit_node` 字段可让内嵌客户端选别人出口(当前无需)。

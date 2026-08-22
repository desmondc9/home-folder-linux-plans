# Android sing-box 客户端配置 — 设计文档

- 日期:2026-08-22
- 目标:基于本机 Kubuntu `/etc/sing-box/config.json`(sing-box 1.13.19,VLESS+Reality+TPROXY 分流网关),产出一份 **Android 版 sing-box (SFA 1.13.19) 客户端配置**,DNS 分流 / 流量分流 / 自定义 ruleset 语义与本机 1:1 一致,并在本机 redroid 容器里实测验证。

## 背景与目标

本机已有一套成熟的 sing-box 分流网关(见 `~/Notebook/sing-box-分流网关/` 知识库):DNS 按域名分流(国内→AliDNS 223.5.5.5,国外→Cloudflare DoH 经 VLESS 防投毒),流量按 rule-set 分流(custom-* > geosite-cn+geoip-cn→direct > geosite-greatfire→proxy > final=proxy),并支持本地 source 格式自定义 ruleset override。用户需要在 Android 手机上获得同样的行为:

1. DNS 国内/国外自动切换(阿里 / Cloudflare)
2. 流量按 GEOSITE + GEOIP 自动分流(direct / proxy)
3. 自定义 ruleset,可对特定域名/IP override 为直连或代理
4. 尽量无感知(透明);TPROXY 在无 root 真机上不可行,采用 tun + auto_route + strict_route(SFA 官方标准方案)

## 范围

- 交付:手机 profile 配置(config.json)+ 两个自定义 ruleset 文件 + 导入说明
- 验证:redroid(本机 podman Android 15 容器,root)内安装官方 SFA 1.13.19 客户端实测
- 不包含:VPS 服务端改动、本机网关改动、其他平台客户端

## 关键设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 客户端 | 官方 SFA `SFA-1.13.19-universal.apk`(GitHub Releases) | 官方客户端,与 core 同版本 |
| 透明方式 | tun + auto_route + strict_route,stack=gvisor | 无 root 真机上 TPROXY 不可行;tun+VPNService 是官方"最新、稳定、无感知"方案 |
| tun 地址 | 172.18.0.1/30 + fdfe:dcba:9876::1/126,mtu 9000 | sing-box 官方文档示例;实测可用 |
| tun 字段 | 用合并字段 `address`(不用 `inet4_address`) | **1.13 已移除旧字段**(`check` 报 "legacy tun address fields … removed in 1.12.0"),文档站的 `dns_mode` 等字段是 1.14 的,不能用 |
| ruleset 路径 | 绝对路径 `/storage/emulated/0/Android/data/io.nekohasekai.sfa/files/…` | SFA 相对路径基准实测为该外部 files 目录;绝对路径消除 CWD 歧义 |
| 分流语义 | 完全复制本机(含 QUIC block、hijack-dns、custom-direct 生命线) | 用户要求"与本机一致" |
| routing_mark | 移除 | 本机 nftables 防回环专用,Android 无意义 |
| mixed inbound | 移除 | 手机 profile 只留 tun |
| 测试方式 | SFA App 实测为主,裸 core(root+tun)兜底 | 用户确认的测试策略 |

## 踩坑记录(详见 implementation.md 与 Notebook 深坑清单)

1. **redroid 缺 `/dev/tun`**:Android 的 netd/VpnJni 打开 `/dev/tun` 建 tun(报 `VpnJni: Cannot allocate TUN: Bad file descriptor`),redroid 只有 `/dev/net/tun`。解法:`mknod /dev/tun c 10 200`。
2. **`dns_mode`/`dns_address` 是 1.14 字段**,文档站是最新版;以 1.13.19 二进制 `check` 为准。
3. **SFA 导入校验会真跑 core**(本地 ruleset 读失败=导入失败);`file:///sdcard/...` 被 scoped storage 挡(EACCES),content URI 被 SAF 强制挡;可用 `file:///data/data/io.nekohasekai.sfa/files/…`(应用私有目录)触发导入。
4. **SFA 的 "Create service" 是错误对话框标题**(error_create_service),不是确认框。
5. **VPN 建立后 adb 被 VPN 吞掉**(redroid 的本地子网未豁免);测试 profile 加 `route_exclude_address: ["10.89.0.0/16"]` 保住控制通道——交付配置不含此项(真机 VpnService 自动豁免本地子网)。
6. redroid 里静态 curl 无 resolv.conf 可用 → 测试用 busybox nslookup(查询进 tun 被 hijack)+ curl --resolve;设备 toybox 无 awk/`{n,m}` 正则,管道解析细节见 implementation.md。

## 验收标准(全部在 redroid 内实测通过)

- a. DNS:国内域名(baidu→a.shifen.com CDN、myip.ipip.net 5-10ms)走 AliDNS;国外域名(google→真实 142.251.x、api.ipify.org 578ms DoH)走 Cloudflare DoH 经 VLESS
- b. 分流:api.ipify.org→VPS IP、myip.ipip.net→家宽、google/github→代理连通、taobao→直连+国内 CDN
- c. override:custom-proxy 加入 ipip.net 后出口由家宽翻转为 VPS;裸 core 阶段双向(custom-direct 加 ipify.org)亦验证

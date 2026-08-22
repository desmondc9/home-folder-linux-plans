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

## 复盘要点

- **文档站 ≠ 目标版本**:sing-box 官方文档展示 1.14+ 字段(dns_mode),1.13.19 会报 unknown field;以目标版本二进制 `check` 为准
- **SFA 相对路径基准** = `/storage/emulated/0/Android/data/io.nekohasekai.sfa/files/`(从导入报错信息中实测得出)
- **VpnJni EBADF** = `/dev/tun` 缺失,与 TUNSETIFF busy 是两个不同的坑
- redroid 无 VPN 本地子网豁免 → 测试必须显式 route_exclude_address,否则 adb 失联
- 静态 musl curl 在 Android 上不用 netd resolver(空 resolv.conf → "Could not resolve host"),测试需 nslookup+--resolve 组合

# Windows 11 Exit Node + sing-box TUN 分流 实施计划

> **执行环境特殊**:AI 运行在该 Windows 11 的 WSL2 里,Windows 侧操作经 interop(`powershell.exe` 等)代跑;涉及 UAC 提权/装服务的步骤标 `[提权]`,由用户在一个管理员 PowerShell 里粘贴执行。VPS 侧(批准路由)AI 从 WSL ssh 代跑。

**Goal:** desktop-j7nbnu4(100.64.0.7)成为第三个 Exit Node,sing-box TUN 模式分流,与笔记本/VPS 出口并存。

**Tech Stack:** sing-box v1.13.19(Windows amd64)/ Tailscale(已装已入网)/ headscale 0.29.3(VPS)

**Spec:** [spec.md](spec.md)

## Global Constraints

- **不破坏 mirrored WSL**(podman 工作流刚需)——每个 Task 结束跑 WSL 回归:localhost 互通 + `podman ps` + 外网解析
- **不破坏 tailscale**(已入网,node id 7)——每个 Task 结束 `tailscale.exe status` 在线
- **一键回退**:`sc stop sing-box`(TUN 拆、路由自动消失)+ `tailscale set --advertise-exit-node=false`
- **机密红线**:uuid/pbk 只写入 Windows 本地 `C:\ProgramData\sing-box\config.json`,绝不进 ~/plans 仓库(占位符 + 提取命令)
- **v2rayN(10808)验证期全程保留**,最后才退役

---

### Task 0: 前置事实核查 ✅ 2026-09-12

- [x] 本机 = Windows 11 物理机 + WSL2 mirrored(见 spec.md 现状表)
- [x] Tailscale 已入 headscale(node id 7,在线,ControlURL 正确,ExitNodeID 为空)
- [x] 公网 IPv6 240e: ✓;netcheck bwg-derp 131.4ms ✓
- [x] v2rayN/xray 占 10808,10809 空闲 ✓
- [x] VPS ssh 免密 + sudo -n headscale 可用 ✓
- [ ] 两个 tailscaled.exe 进程:待 Task 1 重启后复查(若仍在,查 `Get-CimInstance Win32_Process` 父子关系)

### Task 1: 安装 sing-box 二进制(免提权)

**Files:**
- Create: `C:\Users\Desmond\Apps\sing-box\sing-box.exe`(免提权目录,不动 Program Files)

- [x] **Step 1: 下载 v1.13.19 Windows zip** ✅ 2026-09-12(GitHub 直连 6MB/s,未走代理)
- [x] **Step 2: 解压到 `C:\Users\Desmond\Apps\sing-box\` 并校验** ✅ 1.13.19 windows/amd64(with_gvisor/with_utls 等 tag 齐)
- [x] **Step 3: `sing-box.exe service --help`** ✅ **无 `service` 子命令**(1.13.19 实测,unkown command)→ Task 3 改用 WinSW v2.12.0(`sing-box-service.exe` + xml 已就位)
- [ ] **Step 4: 重启 Windows** `[用户执行]`(顺带清理双 tailscaled 进程;重启后 WSL/interop/tailscale 回归检查)

### Task 2: 配置部署与本地校验(免提权) ✅ 2026-09-12

**Files:**
- Create: `C:\Users\Desmond\Apps\sing-box\config.json`(uuid/pbk 已填真值,不入库)
- Create: `C:\Users\Desmond\Apps\sing-box\rules\custom-direct.json` / `custom-proxy.json`

- [x] **Step 1: 从本机 v2rayN 提取节点参数** ✅ v2rayN 便携版在 `D:\v2rayN-windows-64\binConfigs\config.json`(xray 运行配置);节点与笔记本完全一致(104.194.83.82:45575 / vision / www.ebay.com / chrome / short_id 空)
- [x] **Step 2: 发布三个文件到 Apps 目录** ✅(jq 注入真值,占位符版留在档案)
- [x] **Step 3: 校验配置** ✅ `sing-box check` → CONFIG_CHECK_OK

### Task 3: 安装服务并首启(提权,一次 UAC) ✅ 2026-09-12

> sing-box 1.13.19 **无 `service` 子命令**(实测),Windows 服务用 **WinSW** 包装:`sing-box-service.exe` + 同名 xml,`install` 后即标准 Windows 服务。实际执行:UAC 由 AI 从 WSL `Start-Process -Verb RunAs` 触发,用户点一次「是」。

- [x] **Step 1: 部署 WinSW** ✅ v2.12.0(GitHub 直连下载)+ `sing-box-service.xml`(id=sing-box,自动启动,崩溃 5s 重启,日志 roll 到 `logs\`)
- [x] **Step 2: [提权] 安装并启动服务** ✅ `elevate-install.ps1`(transcript 留 `install-result.txt`);日志确认 TUN 创建、`process_name` 规则对 `tailscaled.exe` 生效、VLESS 出站连接成功
- [x] **Step 3: 立即回归** ✅ tailscale 在线 / WSL localhost 互通 / podman 正常 / v2rayN 10808 未受影响
- [x] **Step 4: 本机分流验收** ✅(WSL 测,经 mirrored 宿主栈):myip.ipip.net → 114.92.157.156 上海电信;api.ipify.org → 104.194.83.82;google 200(0.88s)
- [x] **Step 5: WSL 分流验收** ✅ **mirrored WSL × TUN 实测共存正常**(spec 风险 #1 解除):WSL 出国外走 VPS、国内出家宽;podman 正常
- [x] **补:Windows 原生流量验证** ✅ myip.ipip.net → 240e: 家宽 v6 出口;api.ipify.org → VPS
- [x] **回退开关就位**:`stop-service.ps1` = `sc.exe stop sing-box`(实测未需用)

### Task 4: advertise exit node + headscale 批准 ✅ 2026-09-12

- [x] **Step 1: `tailscale.exe set --advertise-exit-node=true`** ✅(**免提权直接成功**,无需 UAC;Windows 客户端 CLI 非 admin 可改此 pref,与预期不同,记录在案)
- [x] **Step 2: [AI 从 WSL 代跑] 批准路由** ✅ `sudo headscale nodes approve-routes --identifier 7 --routes 0.0.0.0/0,::/0` → "Node updated"(注意:0.29 无 `routes list` 命令,验证走客户端)
- [x] **Step 3: 客户端可见性** ✅ VPS 侧 `tailscale exit-node list` 出现 `desktop-j7nbnu4.tailnet.internal`;Windows 自身 `ExitNodeID: ""`(不自选出口,防环)

### Task 5: 端到端验收 `[用户执行]`

- [x] **Step 1: Android(oneplus-15,家 WiFi,Exit Node=desktop-j7nbnu4)首次测试** ⚠️ 国内正常,**国外(youtube 等)不可达** → 见下方 Task 5b 根因记录
- [ ] **Step 2: 修复后复测** Android:youtube/Google 全量恢复(待用户确认)
- [ ] **Step 3** iPad(4G)同上
- [ ] **Step 4** iPhone(desmond-iphone-11)同上
- [ ] **Step 5** 切回笔记本出口/VPS 出口/无出口,均正常(并存互不影响)

### Task 5b: 出口客户端国外流量走 DIRECT 的根因与修复 ✅ 2026-09-12(systematic-debugging)

**现象**:Android 经 Windows 出口,国内站正常、GFW 域名全灭。本机(Windows/WSL)代理腿健康(api.ipify.org→VPS)。

**证据链**:

1. tailscale status:oneplus-15 `active; direct 192.168.31.189`——隧道与 P2P 健康且流量 6MB+
2. sing-box 日志(09:51–09:52 手机测试窗口):`open connection to [2001:4860:4844:400::]:443 using outbound/direct[direct]: i/o timeout`——**Google/Facebook 目的走了 direct 直出**(另见 `dns: cached A www.youtube.com → 142.251.x` 真实 IP,DNS 干净,排除 DNS 投毒)
3. 推理:能到 `direct` 的规则仅 4 条,排除 `ip_is_private`/空 `custom-direct`/`geosite-cn` 后唯一剩 **`process_name: [tailscaled.exe,...] → direct`**(部署配置 jq 复核规则序确认)

**根因**:Windows 上 **exit node 转发的客户端流量在 sing-box 进程归因时归属转发者 `tailscaled.exe`**(日志 `router: found process path: C:\Program Files\Tailscale\tailscaled.exe` 佐证),命中本为"防 tailscaled 自身回环"加的 process_name 规则,被整体放行 direct → 手机流量家宽裸奔,GFW 域名死。笔记本原版用 fwmark 0x80000(只标记 tailscaled 自身 socket)不会有此误伤——**mark 不会沾到转发流量,process_name 会**。

**修复(最小变更)**:删除该 process_name 规则(其保护对象已被覆盖:tailscaled 关键流量→VPS 双栈 IP 在 `route_exclude_address`;MagicDNS 上游查询是 DNS 协议,被更早的 `hijack-dns` 截走)。部署配置与档案配置同步删除,`sing-box check` 过,服务重启(再次 UAC)。

**验证**:本机回归全绿(国内家宽/国外 VPS/youtube 200/tailscale 在线/podman OK),无回环。**手机复测待用户执行(Step 2)**。

**教训**:"本机流量正常"不能外推"转发流量正常"——本地 socket 有真实属主(归因不受影响),转发流量才会撞上进程归因的坑。验收必须含真实出口客户端。

### Task 6: 稳定期与收尾

- [ ] **Step 1: 观察 3-7 天**(日常使用 + 偶发断流记录;重点 mirrored WSL 稳定性)
- [ ] **Step 2: v2rayN 退役** ✅ 2026-09-12 用户已关闭(10808 消失,sing-box 10809 独立验证健康;CLAUDE.md 代理段已同步改写)
- [x] **Step 3: 富途 rule-set 平移**(2026-09-12 追加,原计划无此步)✅ 见下 Task 6b
- [ ] **Step 4: strict_route 评估**:试开 true → 回归 tailscale/WSL/串流;异常即回 false 并记录
- [ ] **Step 5: 重启 Windows 清理双 tailscaled 进程**(稳定期进行)
- [ ] **Step 6: 文档**:本档案实施结果回填;`~/Notebook/Tailscale-Headscale-DERP/`(Windows 侧或在笔记本上)补第三出口条目;README 索引已加
- [ ] **Step 7: 自定义规则用法登记**:编辑 `C:\Users\Desmond\Apps\sing-box\rules\custom-{direct,proxy}.json` 数组后 `sc stop sing-box && sc start sing-box`

### Task 5c: 出口客户端国内流量慢/图片挂 — 根因:tailscaled Windows 用户态转发天花板(systematic-debugging)✅ 2026-09-12 定位

**现象**:Android 经 Windows 出口,国内站慢、图片大量加载失败;国外正常。

**排除项(全部实测无罪)**:sing-box 配置(本机同栈 16MB/s 拉完 38MB)、direct/proxy 腿、DNS(解析干净且快)、手机 WiFi 链路(5GHz ch40 96% PHY 961Mbps,ping 4ms)、路由器/ISP(VPS 直连 35MB/s)、QUIC reject(回退不致停滞)。

**证据链(受控实验)**:

| 路径 | 吞吐 | 结论 |
|---|---|---|
| WSL 本机 → TUN → sing-box direct → 阿里云 | **16 MB/s** | sing-box 栈健康 |
| VPS 直连 → 阿里云 | 35 MB/s | 线路健康 |
| **VPS 经 Windows 出口(有 sing-box)** | **~1 MB/s(38MB/38s)** | 转发路径瓶颈 |
| **VPS 经 Windows 出口(无 sing-box,服务停)** | **~0.6–0.9 MB/s** | **瓶颈与 sing-box 无关** |
| 手机实测(clash_api 字节速率) | 起步 ~470KB/s,2–3MB 后停滞、连接被杀 | 与 RST 风暴签名吻合(151 次客户端侧 abort + 40 次远端 RST,主落在手机流) |

**根因**:Windows 上 tailscaled 对 exit node 客户端流量的转发走**用户态网络栈**(WG 封解密 + wintun 逐包穿越用户态),聚合吞吐天花板 ~8Mbps 量级,持续长流在压力下停滞——这是 Tailscale-on-Windows 的已知架构限制(Linux 出口走内核转发,是笔记本出口当年表现正常的根本原因)。非配置问题,config 级无解。

**诊断彩蛋**:`tailscale up` 改 prefs 需重述全部非默认 flag(VPS 实测踩中),改单个 pref 一律用 `tailscale set`;VPS 上"通告出口"与"使用出口"互斥,测试前须 `set --advertise-exit-node=false`。

**修复方向(架构选择,非 config)**:

1. **手机上网不走 Windows 出口**:启用手机本地 SFA sing-box 客户端(2026-08-22-1404 已部署,分流语义 1:1)——国内 4G 直连、国外手机直连 VPS VLESS,全程线速,不依赖任何出口节点;Tailscale 保留但不开 exit,仅用于访家(Moonlight/SSH)。**注意**:笔记本 `/etc/sing-box/android/config.json` 尚存已知 `outbound: block` 旧写法(2026-09-03-1824 档案记录),重启使用前需同步修为 `action: reject` 并平移 futu 规则
2. **iPad(iOS 单 VPN 互斥,无 SFA)**:笔记本出口(内核转发,快)醒着时用;否则 VPS 出口(全局美国,youtube 可用)或 Windows 出口(知晓 8Mbps 限制)
3. Windows 出口保留通告(轻量浏览可用),本文档即容量说明

### Task 6b: 富途 37 域名 rule-set 平移(源档案 [../2026-09-03-2047-futu-domain-audit/](../2026-09-03-2047-futu-domain-audit/implementation.md))✅ 2026-09-12

沿用笔记本"独立 rule-set 文件"方案(非嵌入 custom-proxy.json):

- `rules/futu.json`(37 个 domain_suffix,与笔记本同源)→ 部署至 `C:\Users\Desmond\Apps\sing-box\rules\futu.json`
- config 三处注册:route `futu → proxy`(置于 custom-proxy 之后)、dns `futu → cfdoh`、rule_set local source;另加 `process_name: [FTNN.exe, CrashReporter.exe, FTWebRender.exe, LaunchCheck.exe, LiveUpdate.exe] → proxy` 兜底裸 IP 行情线
  - **Windows exe 名与笔记本不同**:FTWeb→`FTWebRender.exe`,无 NNPython,多出 `LaunchCheck/LiveUpdate.exe`(更新器,枚举自 `D:\FTNN\app\16.32.17708\`)
  - process_name 规则安全性:列表只含富途自家 exe,转发流量归因 tailscaled.exe 不在列表——Task 5b 的误伤模式不复现
- `experimental.clash_api: 127.0.0.1:9090`(对齐笔记本验证口)
- 备份 `config.json.bak-20260912-futu`;`sing-box check` 过;UAC 重启
- **验证**:`www.futunn.com` → cfdoh 解析(EdgeOne 国际边缘 43.175.134.104)→ `outbound/vless[proxy]` 连接 ✓;clash_api `/version` 200 ✓;分流回归(国外 VPS)✓

## 回退总开关

```powershell
# [提权]
sc stop sing-box
tailscale.exe set --advertise-exit-node=false
```

VPS 侧(如需彻底移除):`ssh desmond@100.64.0.4 'sudo headscale nodes approve-routes --identifier 7 --routes ""'`。所有改动可逆,mirrored WSL / v2rayN / headscale / 笔记本零改动。

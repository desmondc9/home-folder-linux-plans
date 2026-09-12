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
- [ ] **Step 2: v2rayN 退役**:退出 + 取消开机自启(xray 服务端在 VPS 不动);WSL podman 代理约定 10809 继续有效
- [ ] **Step 3: strict_route 评估**:试开 true → 回归 tailscale/WSL/串流;异常即回 false 并记录
- [ ] **Step 4: 文档**:本档案实施结果回填;`~/Notebook/Tailscale-Headscale-DERP/`(Windows 侧或在笔记本上)补第三出口条目;README 索引已加
- [ ] **Step 5: 自定义规则用法登记**:编辑 `C:\Users\Desmond\Apps\sing-box\rules\custom-{direct,proxy}.json` 数组后 `sc stop sing-box && sc start sing-box`

## 回退总开关

```powershell
# [提权]
sc stop sing-box
tailscale.exe set --advertise-exit-node=false
```

VPS 侧(如需彻底移除):`ssh desmond@100.64.0.4 'sudo headscale nodes approve-routes --identifier 7 --routes ""'`。所有改动可逆,mirrored WSL / v2rayN / headscale / 笔记本零改动。

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

### Task 3: 安装服务并首启(提权,一次 UAC) `[用户执行,AI 供逐条命令]`

> sing-box 1.13.19 **无 `service` 子命令**(实测),Windows 服务用 **WinSW** 包装:下载 `WinSW-x64.exe` → 改名 `sing-box-service.exe` + 同目录 `sing-box-service.xml`,`install` 后即标准 Windows 服务(supports start/stop/restart + 崩溃自动重启)。首启也可先在提权控制台前台跑 `sing-box run`,验证通过再装服务。

- [ ] **Step 1: 部署 WinSW**(AI 已从 WSL 下载放置,含 xml)
- [ ] **Step 2: [提权] 安装并启动服务**:`sing-box-service.exe install` → `sc start sing-box`;看日志(`Apps\sing-box\logs\` 或 WinSW roll 日志)确认 TUN 创建 + rule-set 全部 updated
- [ ] **Step 3: 立即回归**:Windows 上网 / `tailscale.exe status` 在线 / WSL localhost 互通 + podman / v2rayN 10808 可用——任何异常 → `sc stop sing-box` 回退并诊断
- [ ] **Step 4: 本机分流验收**:
  - `curl myip.ipip.net` → 家宽 IP
  - `curl api.ipify.org` → 104.194.83.82
  - google.com 可访问;nslookup 走向检查(解析结果非投毒段)
- [ ] **Step 5: WSL 分流验收**:WSL 内 `curl myip.ipip.net`(家宽)与 `curl api.ipify.org`(VPS)——mirrored 流量确已进分流

### Task 4: advertise exit node + headscale 批准

- [ ] **Step 1: `[提权]` `tailscale.exe set --advertise-exit-node=true`**
- [ ] **Step 2: [AI 从 WSL 代跑] 批准路由**(node id 7):

```bash
ssh desmond@100.64.0.4 'sudo headscale nodes approve-routes --identifier 7 --routes 0.0.0.0/0,::/0'
```

- [ ] **Step 3: 客户端可见性**:`tailscale.exe exit-node list` 出现 desktop-j7nbnu4;确认 Windows 自身 **ExitNodeID 仍为空**(不自选出口)

### Task 5: 端到端验收 `[用户执行]`

- [ ] iPad(4G,Shadowrocket 关):Exit Node 选 desktop-j7nbnu4 → `myip.ipip.net` 家宽 IP;google 可访问且 `api.ipify.org` = VPS;Moonlight 串流笔记本正常(tailnet 内部流量不经 sing-box)
- [ ] Android 同上
- [ ] iPhone(desmond-iphone-11)同上
- [ ] 切回笔记本出口/VPS 出口/无出口,均正常(并存互不影响)

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

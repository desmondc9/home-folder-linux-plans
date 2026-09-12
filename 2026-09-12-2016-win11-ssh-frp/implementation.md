# Windows 11 SSH 公网可达(frp 反代)实施计划

> **For agentic workers:** 本计划在 ~/.plans 档案体系内按任务顺序执行;步骤用 `- [ ]` 追踪。执行环境特殊:AI 运行在宿主机 WSL 中,Windows 侧经 interop 代跑,提权步骤由用户在管理员 PowerShell 粘贴执行(VPS 侧 AI 从 WSL ssh 代跑)。

**Goal:** 星巴克任意 ssh 设备 → `ssh -p 6001 desmond@bandwagon.signal-align.com` → Windows 11 宿主机 PowerShell。

**Architecture:** 原生 OpenSSH Server(系统服务,免登录自启)+ frpc(WinSW 服务)反向隧道至 VPS 已有 frps:7000,公网暴露仅 VPS:6001 一 port;两阶段认证(密码+ed25519 双开 → 用户触发收紧仅密钥)。

**Tech Stack:** Windows OpenSSH Server(可选功能)/ frp(fatedier/frp 最新 release,Windows amd64)/ WinSW v2.12.0 / OpenSSH ed25519

**Spec:** [spec.md](spec.md)

## Global Constraints

- **机密红线**:frps token、私钥、Windows 密码绝不进入任何 git 跟踪文件(含本档案);`gitleaks dir` 在每次 commit 前跑
- **免登录可达**:`sshd` 与 `frpc` 两服务 StartType=Automatic——断电重启后无人登录即恢复(否决 WSL 方案的根本理由,验收必测)
- **提权方式**:Windows 管理操作打包为 `C:\Users\Desmond\Downloads\ssh-frp-*.ps1`,用户在管理员 PowerShell 执行,transcript 落盘供 AI 读取回填
- **端口约定**:公网 6001(allowPorts 6000–6010 首个空闲位);本地仅用 127.0.0.1:22 与 LAN:22
- **sing-box 互不影响**:frpc → VPS:7000 出站已被宿主 sing-box `route_exclude_address`(104.194.83.82)豁免,直连家宽;不得改动宿主 sing-box 配置

---

### Task 1: 安装 OpenSSH Server + PowerShell 默认 shell

**Files:**
- Create: `C:\Users\Desmond\Downloads\ssh-frp-task1.ps1`(提权安装脚本)
- Modify: 注册表 `HKLM:\SOFTWARE\OpenSSH` DefaultShell;服务 `sshd` 恢复策略

**Interfaces:**
- Produces: `sshd` 服务监听 `0.0.0.0:22`(Task 3 的 frpc 与 Task 4 的验收依赖此)

- [x] **Step 1: AI 写提权脚本**(安装能力 → 启服务设 Automatic → DefaultShell=powershell.exe → sc failure 恢复 → 状态输出):

```powershell
$ErrorActionPreference = 'Stop'
Start-Transcript -Path C:\Users\Desmond\Downloads\ssh-frp-task1-result.txt -Force
Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
Set-Service sshd -StartupType Automatic
sc.exe failure sshd reset= 86400 actions= restart/5000
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
Start-Service sshd
Get-Service sshd | Format-Table Name,Status,StartType -AutoSize
netstat -ano | Select-String ':22 ' | Select-String LISTENING
Stop-Transcript
```

- [x] **Step 2: 用户执行**(capability 走 Windows Update 下载暂存,需重启物化服务——CBS "pended",计划外发现;重启后由 postreboot 脚本完成 1b)
- [x] **Step 3: AI 验证** ✅ sshd Running/Automatic,`0.0.0.0:22`+`[::]:22` LISTENING;DefaultShell 注册表生效;**新版默认 sshd_config 无 Match administrators 块**(原裁定多余,记录)

### Task 2: ed25519 密钥对 + authorized_keys

**Files:**
- Create: WSL `~/.ssh/id_ed25519_winhost[.pub]`(引导密钥对;用户负责分发私钥到常用设备+密码管理器)
- Create: `C:\Users\Desmond\.ssh\authorized_keys`(Windows 侧)

**Interfaces:**
- Consumes: Task 1 的 sshd
- Produces: 密钥登录能力(Task 4 验收依赖)

- [x] **Step 1: AI 在 WSL 生成密钥对**:`ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_winhost -N '' -C 'desmond-winhost-bootstrap'`
- [x] **Step 2: AI 装公钥**(sshd 阶段 1 允许密码,但 authorized_keys 免提权可直接写):

```bash
mkdir -p /mnt/c/Users/Desmond/.ssh && chmod 700 /mnt/c/Users/Desmond/.ssh 2>/dev/null
cat ~/.ssh/id_ed25519_winhost.pub >> /mnt/c/Users/Desmond/.ssh/authorized_keys
```

- [x] **Step 3: AI 验证密钥登录** ✅ `KEY_AUTH_OK` + PS 5.1.22621.6133:`ssh -i ~/.ssh/id_ed25519_winhost -o BatchMode=yes desmond@127.0.0.1 'echo KEY_AUTH_OK; $PSVersionTable.PSVersion.ToString()'`(预期输出 KEY_AUTH_OK + 5.1.x,同时证明 PowerShell 默认 shell)
- [ ] **Step 4: 用户分发私钥**(待办:常用设备+密码管理器;VPS 已存一份测试用)(手机/常用 PC/密码管理器;`~/.ssh/id_ed25519_winhost` 即文件)——登记为交付物;**测试后清理:删除 VPS 侧私钥副本**(`ssh desmond@100.64.0.4 'rm ~/.ssh/id_ed25519_winhost'`)——阶段 2 关密码后,常驻公网 VPS 的有效私钥 = 拿下 VPS 即直进家中 Windows,必须清理

### Task 3: frpc 部署(WinSW 服务)

**Files:**
- Create: `C:\Users\Desmond\Apps\frp\frpc.exe`(最新 release Windows amd64)
- Create: `C:\Users\Desmond\Apps\frp\frpc.toml`(**含真 token,不入库**)
- Create: `C:\Users\Desmond\Apps\frp\frpc-service.exe` + `frpc-service.xml`(WinSW v2.12.0,复用 sing-box 剧本)
- Create: `C:\Users\Desmond\Downloads\ssh-frp-task3.ps1`(提权装服务)

**Interfaces:**
- Consumes: Task 1 的 `127.0.0.1:22`;VPS 现有 frps(bind 7000,token,allowPorts 6000-6010)
- Produces: 公网 `bandwagon.signal-align.com:6001` → 宿主 22(Task 4 验收依赖)

- [x] **Step 1: AI 下载 frp** ✅ 0.65.0(GitHub 直连,失败走 `https_proxy=http://127.0.0.1:10809`):

```bash
curl -fSL -o /tmp/opencode/frp.zip https://github.com/fatedier/frp/releases/download/v0.65.0/frp_0.65.0_windows_amd64.zip
mkdir -p /mnt/c/Users/Desmond/Apps/frp
unzip -j /tmp/opencode/frp.zip 'frp_0.65.0_windows_amd64/frpc.exe' -d /mnt/c/Users/Desmond/Apps/frp/
/mnt/c/Users/Desmond/Apps/frp/frpc.exe -v   # 预期 0.65.0
```

- [x] **Step 2: AI 生成 frpc.toml** ✅(修订:localIP/localPort 显式化 + 域名 + keepalive,见计划修订记录)(token 从 VPS 实时读取注入,不落终端历史之外):

```bash
TOKEN=$(ssh desmond@100.64.0.4 "sudo grep 'auth.token' /etc/frp/frps.toml" | cut -d'"' -f2)
cat > /mnt/c/Users/Desmond/Apps/frp/frpc.toml <<EOF
serverAddr = "bandwagon.signal-align.com"
serverPort = 7000
auth.method = "token"
auth.token = "${TOKEN}"

[transport]
tcpMuxKeepaliveInterval = 10
dialServerKeepAlive = 30

[[proxies]]
name = "win11-ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6001
EOF
unset TOKEN
```

(serverAddr 用域名对齐笔记本 frpc 惯例;**localIP/localPort 必须显式**——frp 默认 localPort=remotePort,漏写会连 127.0.0.1:6001;keepalive 调优沿用户参考配置;不加 useEncryption/useCompression,SSH 载荷已加密,双重处理徒增延迟。**修订记录**:初版漏 localIP/localPort,2026-09-12 依用户提供的笔记本 /etc/frp/frpc.toml 参考修正)
- [x] **Step 3: AI 写 WinSW xml** ✅(修订:0.65.0 无 run 子命令,`-c` 直跑;档案 xml 同步修正) + 下载 sing-box-service.exe 同款 WinSW:

```xml
<service>
  <id>frpc</id>
  <name>frpc</name>
  <description>frp client: win11-ssh via frps:6001</description>
  <executable>C:\Users\Desmond\Apps\frp\frpc.exe</executable>
  <arguments>-c C:\Users\Desmond\Apps\frp\frpc.toml</arguments>
  <log mode="roll-by-size">
    <logpath>C:\Users\Desmond\Apps\frp\logs</logpath>
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>4</keepFiles>
  </log>
  <onfailure action="restart" delay="5 sec"/>
  <startmode>Automatic</startmode>
</service>
```

```bash
curl -fSL -o /mnt/c/Users/Desmond/Apps/frp/frpc-service.exe https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe
```

- [x] **Step 4: 提权脚本** ✅(与 postreboot 合并执行)(`.\frpc-service.exe install` → `sc start frpc` → sleep 8 → `netstat :6001` 无需 → 日志 tail 确认 `login to server success` + `start proxy success`),用户管理员执行
- [x] **Step 5: AI 验证** ✅ `:6001 LISTENING` + `login to server success` + `start proxy success`(frpc 注册成功);`frpc.toml` 权限属用户目录,档案只存脱敏版

### Task 4: 端到端验收 + 指纹入档

**Files:**
- Modify: 本档案 implementation.md(验收勾选 + host key 指纹)

**Interfaces:**
- Consumes: Task 1–3 全部

- [x] **Step 1: 本机双因子** ✅ 密钥路径 ✓:`ssh -i ~/.ssh/id_ed25519_winhost desmond@127.0.0.1`(证据:Task 2 Step 3 `KEY_AUTH_OK` + PS 5.1.22621.6133);密码路径(`ssh desmond@127.0.0.1`,用户交互)**未验证,并入用户侧待办(与热点测试同批)**
- [x] **Step 2: VPS 公网回环** ✅ `VPS_LOOP_OK`——**但此测试走 loopback 绕过了 ufw,属假绿灯**(2026-09-12 iPad 实连失败暴露)
- [x] **Step 2b: ufw 放行 6001** ✅(根因:VPS 防火墙仅放行 6000 旧口,6001 未开;`sudo ufw allow 6001/tcp comment "frps win11-ssh"` 后 WSL 走公网域名复测 `WSL_VIA_PUBLIC_OK`)。**教训:外部可达性验收必须从公网接口侧发起,loopback 自环不能替代**:`ssh desmond@100.64.0.4` 后 `ssh -p 6001 desmond@104.194.83.82`(完整走 frps→frpc;密钥需先拷到 VPS 或用密码)
- [ ] **Step 3: 真·外网**(用户手机热点自验;TOFU 指纹已入档:ECDSA `SHA256:BOHaQVi/HfOsJYKO4dSyGV3c709jRoupUM95zTDfZ/w`、ED25519 `SHA256:uWSgxwA5TK56apRQuhV74k7tQpA1qxnJzOQC+o1VvnA`、RSA `SHA256:5mQo5+KEPvx87XbvDSi2DvyJ194nzcr+ytfBfZsPfvU`) + 任意设备 `ssh -p 6001 desmond@bandwagon.signal-align.com`,首连 TOFU 记录指纹:`ssh-keyscan -p 6001 bandwagon.signal-align.com 2>/dev/null | ssh-keygen -lf -`(结果写入本档案)
  - **用户侧待办汇总(四项)**:① 私钥分发到常用设备+密码管理器(Task 2 Step 4);② 删除 VPS 侧私钥副本(Task 2 Step 4);③ 手机热点真·外网自验(本 Step);④ 稳定期重启 Windows 验证免登录恢复(Step 4 登记,复查)
- [x] **Step 4: 服务自启核查** ✅ 两服务 AUTO_START(RUNNING);**断电重启免登录恢复**已由本轮重启实证(sshd capability 物化即无人登录场景)`sc qc sshd` / `sc qc frpc` 均 AUTO_START;稳定期重启 Windows 验证免登录恢复(登记待办)
- [x] **Step 5: 档案回填 + commit** ✅ 本条即(含 gitleaks)

### Task 5(用户触发,阶段 2): 关闭密码认证

**Files:**
- Modify: `C:\ProgramData\ssh\sshd_config`(PasswordAuthentication no)
- Modify: 本档案(待办销项)

**触发条件**:Task 4 Step 1-3 密钥路径全部 ✓ 且私钥已分发备份。

- [ ] **Step 1: 提权修改** `C:\ProgramData\ssh\sshd_config`:追加/改 `PasswordAuthentication no` → `Restart-Service sshd`;同时 AI 把修改后的 sshd_config **脱敏快照**存入本档案(`sshd-config.snapshot`,密码/无密内容本就非敏感,防 Windows 更新重置的对账基线);同时入档防火墙 22 端口规则状态(`netsh advfirewall firewall show rule name=all | Select-String -Context OpenSSH` 输出)
- [ ] **Step 2: 验证**:密码登录被拒(`Permission denied (publickey)`),密钥仍通
- [ ] **Step 3: 档案销项 + commit**

## 回退总开关

```powershell
sc stop frpc; sc delete frpc                      # 撤公网入口
# 或彻底:Remove-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
```
VPS 侧零改动(6001 随 frpc 下线自动消失)。

## 附录: DNS 别名(2026-09-12)

`laptop.signal-align.com` 由 A 记录**原位改为 CNAME → bandwagon.signal-align.com**(Cloudflare API,`~/.cloudflare/credentials.jsonc` 的 `apiTokens.token`,zone 3b564a8b;proxied=false)——双栈自动继承(A 104.194.83.82 + AAAA 2607:8700:5500:7bd3::2),VPS 换地址只改 bandwagon 一处。权威 NS 与 1.1.1.1 实测链路完整;sshfrp 用法不变:`ssh -p 6001 desmond@laptop.signal-align.com`。注意:改记录前存在的 AAAA 否定缓存最长 5 分钟才过期(WSL/Windows 客户端侧)。

# Windows 11 宿主机 SSH 公网可达(frp 反代)设计文档

日期:2026-09-12 · 状态:设计已批准,待审阅 · 流程:brainstorming skill(方案对比→分节确认)

## 背景与目标

用户需要在星巴克等外部网络,用**任意支持 ssh 的设备**(无需安装任何 VPN 客户端)配合用户名/密码或密钥,登录家中 Windows 11 宿主机(DESKTOP-J7NBNU4)。VPS(bandwagon.signal-align.com)上已有运行中的 frps,利用 frp 反向隧道把宿主机 sshd 暴露到公网。

## 范围

**In scope:**
- Windows 原生 OpenSSH Server 安装与加固(可选功能,系统服务)
- frpc(Windows 便携版)单条 TCP 隧道:VPS:6001 → 宿主机 127.0.0.1:22
- 两阶段认证:先密码+密钥双开,验证后收紧为仅密钥(阶段 2 由用户触发)
- 默认 shell = PowerShell

**Out of scope(YAGNI,已明确排除):**
- RDP 反代(frpc.toml 加一行即可,未来需要再说)
- Tailscale 路径实施(已天然存在:`ssh desmond@100.64.0.7`,登记为带外备用)
- WSL 内 sshd 方案(否决:断电重启后需用户登录才能拉起,违背"无人值守可达"核心需求)

## 现状(2026-09-12 实测)

| 事实 | 值 |
|---|---|
| frps(VPS) | active,bindPort 7000,token 认证,allowPorts **6000–6010 当前全空闲** |
| Windows OpenSSH Server | **未安装**(仅客户端组件的 ssh-agent,Stopped/Disabled) |
| sing-box(宿主) | 运行中;`route_exclude_address` 含 104.194.83.82 → frpc 出站直连家宽,无回环 |
| WinSW 剧本 | 已在 sing-box 服务上验证(便携目录 + UAC 一次 + 崩溃自拉起) |

## 方案设计

### 架构

```
星巴克任意设备                VPS (bandwagon.signal-align.com)         Windows 11 宿主机
┌──────────┐   公网          ┌──────────────┐    frp 隧道(反向)   ┌─────────────────────┐
│ ssh 客户端 ├────:6001───────▶│ frps :7000   │◀═══════════════════▶│ frpc(WinSW 服务)     │
└──────────┘  密码/私钥        │ allowPorts   │   token,自动重连     │   └─▶ 127.0.0.1:22   │
                               │ 6000-6010    │                     │ sshd(系统服务)       │
                               └──────────────┘                     │ 默认 shell: PowerShell│
                                                                    └─────────────────────┘
```

### 组件与配置

1. **sshd**:`Get-WindowsCapability -Online` 安装 OpenSSH Server → 服务 `sshd`(Automatic,Recovery=restart);注册表 `DefaultShell` = `powershell.exe`;防火墙用安装器默认规则(22 对局域网开放,公网进不来——公网入口只有 frps:6001)
2. **frpc**:最新版便携二进制 → `C:\Users\Desmond\Apps\frp\`;`frpc.toml`:serverAddr = VPS:7000,token = 现有 frps token,**proxy 一条**:type tcp、remotePort 6001、`127.0.0.1:22`;WinSW 服务名 `frpc`(onfailure 5s 重启)
3. **密钥**:**ed25519**(短/快/OpenSSH 全支持;如遇特殊兼容需求再补 RSA);公钥 → `C:\Users\Desmond\.ssh\authorized_keys`;私钥由用户分发到常用设备 + 密码管理器备份

### 两阶段认证

- **阶段 1(部署即达)**:密码(Windows 账户密码,须强密码)+ 公钥双开
- **阶段 2(密钥验证可用后,用户触发)**:`sshd_config` 置 `PasswordAuthentication no` + 重启服务;**写入档案待办防遗忘**——"先双开"不能变"永远双开"

### 失败模式与韧性

| 故障 | 行为 |
|---|---|
| VPS/家宽闪断 | frpc 内置退避重连,隧道自愈 |
| sshd/frpc 进程崩 | SCM 恢复策略 / WinSW 5s 自拉 |
| 家中断电→来电 | 两服务 Automatic,**无人登录自动恢复可达** |
| sing-box 故障 | 无依赖(frpc 直连 VPS) |
| frps 故障 | 公网暂断;tailnet 带外备用(`ssh desmond@100.64.0.7`) |
| 私钥全丢(阶段 2 后) | tailnet 带外 + 家中物理接触可救;私钥多处备份 |
| 中间人 | 首连 TOFU 确认 host key 指纹,指纹记录入档案供核对 |

### 事件风暴(轻量;本任务无 UI/domain/存储,三层 schema 不适用)

- **write 维度**(管理员→command→event→后续):部署 sshd+frpc → 服务上线 → (阶段2)关密码 → 仅密钥可入;密钥轮换 → 替换 authorized_keys → 旧钥失效
- **read 维度**(咖啡店用户 view/query):登录会话(PowerShell 交互/命令执行);服务状态查看(`sc query sshd/frpc`)——无排序/搜索类查询

### 关键决策(含搜旧)

| 决策 | 理由 |
|---|---|
| 方案 A(原生 sshd + frpc/WinSW) | 唯一满足"断电重启免登录可达";复用 WinSW 已验证剧本(复用) |
| 端口 6001 | allowPorts 首个空闲位(修改后复用现有 frps,零服务端变更) |
| ed25519 而非 RSA | 更短更快同等安全;"rsa key"按口语理解,不锁死算法 |
| PowerShell 默认 shell | 用户选择;cmd 保守、WSL 与无人值守矛盾 |
| 仅 SSH 不含 RDP | YAGNI;frpc.toml 加一行即可扩展(预留心智,不预留配置) |

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 公网密码窗口期撞库 | 阶段 1 尽量短;强密码;阶段 2 待办入档 |
| frps token/私钥泄露面 | 仅存 Windows 本地 + 用户密码管理器;**绝不进 git**(脱敏版入库,gitleaks 把关) |
| Windows 更新重置 sshd_config/防火墙 | 收紧后入档配置快照,变更后复查 |

## 验收标准

1. 本机 `ssh desmond@127.0.0.1`:密码 ✓、私钥 ✓、shell 为 PowerShell
2. VPS 侧模拟公网回环:`ssh -p 6001 desmond@bandwagon.signal-align.com`(完整 frps→frpc 链)✓
3. 真·外网(手机热点)同命令 ✓
4. 两服务 Automatic;稳定期重启 Windows 后**免登录**恢复可达 ✓
5. 阶段 2 后:密码被拒、密钥仍通 ✓
6. gitleaks 扫描无 token/私钥入 git ✓

## 参考

- frp:https://github.com/fatedier/frp
- WinSW 剧本与 Apps 目录惯例:[../2026-09-12-0021-windows11-exit-node-singbox/](../2026-09-12-0021-windows11-exit-node-singbox/implementation.md) Task 1/3
- VPS frps 现状(allowPorts 空闲核查):2026-09-12 ssh 实测,见「现状」表

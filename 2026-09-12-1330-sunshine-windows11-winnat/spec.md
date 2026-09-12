# Windows 11 宿主机 Sunshine 安装 — WinNAT/HNS 端口保留致 RTSP 绑定失败 设计与排障记录

日期:2026-09-12 · 状态:修复方案落地中(待重启验证)
- 环境:Windows 11 物理机(DESKTOP-J7NBNU4)(WSL interop 排查)

## 背景与目标

Windows 11 物理机(DESKTOP-J7NBNU4,100.64.0.7,RTX 4060 Laptop)安装 Sunshine(Moonlight 主机端),供 Android(SFA)/iPad/PC/Mac 经 tailnet 用 Moonlight 串流。参考笔记本方案 [../2026-08-19-1302-sunshine-moonlight-tailnet/](../2026-08-19-1302-sunshine-moonlight-tailnet/spec.md)。

## 现象

用户经 `Sunshine-Windows-AMD64-installer.msi`(版本 2026.906.2225.25)安装后 "Sunshine 一直在重启"。

## 根因(systematic-debugging,证据链完整)

1. **事件日志**:`Sunshine.exe 0xc0000005` 固定偏移 `0x1ec59a1`,~20s 一崩(服务不断拉起)——崩溃是**果**(异常退出路径上的崩溃)
2. **Sunshine 日志临终行**(真因):
   `Fatal: Couldn't bind RTSP server to port [48010], An attempt was made to access a socket in a way forbidden by its access permissions`(WSAEACCES)
3. **绑定栈**:Sunshine RTSP 绑 `[::]:48010`(IPv6 通配);v4 通配可绑、v6 不可
4. **`netsh int ipv6 show excludedportrange protocol=tcp`**:**47984–48010 被动态保留**(最初只查 v4 表而漏掉 v6——排障走了一段弯路)
5. **保留持有者不是 winnat**:`net stop winnat` 后 v6 持久保留 add 仍报 "file being used by another process" → 持有者是 **HNS**(Host Network Service;本机 WSL2 **mirrored 模式**的宿主组件)
6. 对照实验(排除项):nvenc 三编码器(h264/hevc/av1)全部就绪;GPU/防火墙/安装本体无罪;控制端口(55123/49000)原生 bind 正常

**结论**:WSL2 mirrored 的 HNS 在 v6 上动态保留了 47984–48010,导致 Sunshine 的 `[::]:48010` RTSP 绑定 WSAEACCES → 进程 Fatal → 异常退出路径 0xc0000005 → 服务拉起 → 死循环。与笔记本 2026-08-19 的 RTSP 绑定故障"同穴位、不同病理"(彼为端口冲突 EADDRINUSE,此为保留区 EACCES)。

## 方案

1. **v4 持久保留**(已成功):TCP 47984–48010、UDP 47998–48002、UDP 48010
2. **v6 持久保留**:当前被 HNS 动态占用加不进 → **开机 SYSTEM 计划任务 `SunshinePortReserve`**(onstart)在 HNS/WSL 认领前重assert全部保留(持久保留写入注册表后,动态分配器会避让)
3. **重启清场**:重启后动态保留清空、持久保留就位、SunshineService(Automatic)绑定成功
4. 附带收获:MSI 不支持 INSTALLDIR 属性,默认装 `C:\Program Files\Sunshine`(配置随安装目录,非 D:\Sunshine)

## 验收标准

- [x] 重启后 `netstat` 显示 47984/47989/47990/48010 LISTENING ✅ 2026-09-12 15:33(`wsl --shutdown` + 服务重启后,四端口 `0.0.0.0` 全监听,单实例无僵尸)
- [x] sunshine.log 无 Fatal,出现 Web UI 提示 ✅(托盘正常,用户已打开 Web UI)
- [ ] Web UI `https://localhost:47990` 可达并设置凭据(用户打开过,`not authorized` = 待设账号密码)
- [ ] Moonlight(Android/iPad)添加主机 `100.64.0.7` 配对成功,串流出画面(tailnet 内部流量经 sing-box route_exclude 豁免,不进 TUN)
- [x] **tailnet 侧四端口可达** ✅ VPS(100.64.0.4)对 100.64.0.7 的 47984/47989/47990/48010 TCP 全通(2026-09-12 15:4x 实测)——sing-box TUN 与入站服务共存无恙
- [ ] 再次重启一次验证持久性(SunshineService 开机先于 WSL 启动,稳态预期成立;待观察)

## 坑位登记(方法论)

1. **排障先查双栈排除表**:`netsh int <ipv4|ipv6> show excludedportrange`,只查 v4 会漏案
2. **WSL mirrored 的 WSL 侧 bind 会污染宿主端口状态**(探测本身改变现场);跨栈测端口用原生进程(node/TcpListener),且注意 WSL 镜像 bind 不受宿主保留约束——结果不可迁移
3. **`net stop winnat` 只清 winnat 的动态保留**,HNS 的保留不受影响;持久保留(`store=persistent`)才是跨重启的防御
4. UAC 触发(`Start-Process -Verb RunAs`)经 WSL interop 不稳定(阻塞/弹窗丢失)——关键安装步骤改为用户手动跑管理员脚本更可靠
5. Sunshine 崩溃循环的日志在 `<安装目录>\config\sunshine.log`(服务包 sunshinesvc.exe + 用户会话 sunshine.exe;僵尸态与笔记本 Task 7 同款)

## 参考

- 笔记本 Sunshine 方案(端口清单/看门狗):[../2026-08-19-1302-sunshine-moonlight-tailnet/](../2026-08-19-1302-sunshine-moonlight-tailnet/implementation.md)
- 用户下载:`C:\Users\Desmond\Downloads\Sunshine-Windows-AMD64-installer.msi` + debuginfo.7z(未用上,日志已定位根因)
- 修复脚本:`sunshine-fix.ps1`(三轮迭代)/`sunshine-fix{,2,3}-result.txt`

## 终局修订(2026-09-12 13:35,第三轮)

上文的"排除区/保留"叙事需要修正——完整因果链分两个纪元:

1. **纪元一(昨晚 22:23 首崩)**:47984–48010 落入动态排除表(winnat/HNS),`[::]:48010` 绑定 WSAEACCES
2. **纪元二(今日排障期)**:排障中从 WSL 用 python 探测绑定了 `[::]:48010` 等端口——**WSL mirrored 的宿主侧端口中继在套接字关闭后泄漏**(对 netstat 隐形、令原生进程 EADDRINUSE/EACCES),即使删除全部排除表项、Sunshine 依然绑不上。控制实验:`:::48111` 与 `:::48010` EADDRINUSE vs `:::55124`/`49000` 正常
3. **自锁插曲**:期间按 Docker 民间偏方加的 `excludedportrange store=persistent` 在本机上**连应用 bind 一起挡**(与偏方语义相反),已全部删除修正
4. **最终修复**:`wsl --shutdown` 清掉全部镜像中继泄漏 → 重启 SunshineService → 端口全自由,绑定成功(WSL 重启后镜像中继重建,会避让已被 Sunshine 持有的端口;开机时 SunshineService 先于 WSL 启动,稳态)

**防复发守则**:
- **永远不要从 WSL bind Sunshine 端口段(47984–48010)做探测**——mirrored 中继泄漏是本机已证实的坑
- 若未来再出现"端口看不见却绑不上",先 `node -e` 原生 bind 对照,再考虑 `wsl --shutdown`
- 排除表用 `netsh int ipv6 show excludedportrange`(双栈都查)仅作诊断;**不要**给应用端口加持久保留

## 交接(待用户执行)

1. Windows 侧管理员 PowerShell:`wsl --shutdown`(WSL 会话终结属预期)
2. 10 秒后:`Restart-Service SunshineService`
3. 验证:`netstat -ano | findstr "479 480"` 有 LISTENING;`https://localhost:47990` 设凭据
4. Moonlight(Android/iPad)加主机 `100.64.0.7` 配对;重启 opencode 会话回填验收

## 尾声:游戏手柄授权问题(2026-09-12 17:49 解决)

新版 Sunshine(2026.x)的手柄虚拟化分层:libvirtualhid(开源库)+ Virtual HID Driver(Windows 驱动,**付费机器授权** $14.99/年 或 $49.99 买断/5 机;LizardByte 商业模式)。**免费替代 = ViGEmBus**(开源 LGPL,GitHub ViGEm/ViGEmBus,项目已归档但 Win11 可用),Sunshine 检测到即自动回退。用户双装(libvirtualhid + ViGEmBus)后 `Restart-Service SunshineService`,日志中全部 gamepad disabled 警告消失 = 回退生效,**未购买授权**。鼠标/键盘/触控本来就不经过此层(SendInput)。

验收终态:四端口 LISTENING ✓ tailnet 可达 ✓ Moonlight(Android/iPad)串流成功 ✓ 手柄支持(ViGEmBus 回退)✓

## 终稿补充(17:55)

用户随后**购买了 Virtual HID Driver 正版授权**($49.99 买断/5 机,支持 LizardByte 上游开发)并激活;`Restart-Service SunshineService` 后最终态:零 gamepad 警告、零 Fatal、四端口正常——libvirtualhid 授权路径接管,ViGEmBus 保留作冗余回退。档案就此封版。

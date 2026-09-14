# Win11 宿主 Sunshine 启动探测全军覆没:所有编码器(含 software)同报 "Failed to locate an output device"

日期:2026-09-14 · 状态:**初诊完成、验证未做、暂停待续**(用户指示先到这里,出现新问题再继续) · 流程:diagnosing-bugs skill(远程日志工件分析 + 已知问题查证;验证循环设计好待在 Win11 机上执行)

- 环境:Windows 11 物理机 DESKTOP-J7NBNU4(笔记本);Sunshine v2026.906.222525(LizardByte 官方版,服务模式,2026-09-12 装机见 [2026-09-12-1330-sunshine-windows11-winnat](../2026-09-12-1330-sunshine-windows11-winnat/));双屏:BOE 内屏 2560×1600@240Hz(主,origin 0,0)+ 小米 XMI "Mi Monitor" 3840×2160@60Hz(扩展,origin 2560,-550),均 150% 缩放、HDR 关;N 卡在位(nvprefs 可读写驱动配置);排查自 Linux/WSL 侧远程分析用户贴出的日志,未在目标机执行命令

## 症状(2026-09-14 00:27 服务启动日志)

```
00:27:28.092 Info: // Testing for available encoders... Trying encoder [nvenc]
00:27:28.619 ~ 00:27:30.538  Error: Failed to locate an output device  ×4 → Encoder [nvenc] failed
(quicksync / amdvce / mediafoundation / software 逐个同样 ×4 失败)
00:27:40.239 Fatal: Unable to find display or encoder during startup.
00:27:40.246 Info: Starting system tray ... Configuration UI available
08:59:09.073 Info: Qt: QtTrayMenu ... System tray created   ← 隔了 8.5 小时
09:15:58 / 09:16:15 Info: Web UI: [127.0.0.1] -- not authorized
```

## 已确认事实(证据链)

1. **不是编码器问题,是屏幕捕获层(D3D11/DXGI Desktop Duplication)拿不到输出设备**:五个编码器(含纯 CPU 的 software)报的是同一个错——编码器只是"陪葬",每编码器 ×4 次 = 采集后端/适配器组合的尝试次数,全灭。
2. **启动时无用户控制台会话**:服务 00:27:27 启动并探测(全灭),`System tray created` 直到 08:59:09 用户登录才出现——8.5h 时间差说明 00:27 时机器刚开机、无人本地登录。DXGI/DDA 在无活动控制台会话下找不到 output 是已知模式([LizardByte #1293](https://github.com/LizardByte/Sunshine/issues/1293) "started remotely headlessly")。
3. **GDI 层能枚举到双屏、DXGI 层却拿不到 output**:同一段日志开头完整枚举了 BOE 内屏 + 小米外屏(分辨率/刷新率/origin 全对)——Windows 显示配置在,但 D3D 设备栈绑不上,两层矛盾指向会话/适配器状态而非"没插显示器"。
4. **`Web UI: not authorized`(09:15)与本案无关**:网页登录密码错/未配对;忘记密码用 `sunshine.exe --creds 用户名 密码` 重置即可。
5. Sunshine **只在启动时探测一次编码器**,失败状态一直挂到下次重启服务——与"之后一直不可用"的预期行为吻合。

## 假设排序(均未验证)

| # | 假设 | 支持证据 | 证伪/确认预测 |
|---|---|---|---|
| 1 | 服务在无人登录时启动,DDA 无 output(#1293 模式) | 时间线(事实 2)强烈支持;该机 09-12 装机时登录状态下探测是成功的 | 本地登录后 `Restart-Service Sunshine` → 日志应出现 nvenc 成功、无 Fatal;若延迟启动/登录后重启服务即恒绿,则确认 |
| 2 | 混合显卡绑错适配器(#260) | 笔记本内屏通常挂核显,N 卡无 output | 设置→显示→图形→`sunshine.exe` 设"高性能";或 Sunshine 配置手动指定 NVIDIA adapter → 若变绿则确认 |
| 3 | 显卡驱动坏(#939/#3447 路数) | 未排查 | DDU 干净重装 N 卡 + 更新核显驱动 |
| 4 | 虚拟/间接显示器驱动冲突 | 未排查(该机近期装过 libvirtualhid 等虚拟设备驱动,见键鼠档案) | 禁用 spacedesk/Parsec VDD/IddSampleDriver 等再试 |

注:2026-09-13 晚该机接连出过 USB 键鼠挂死与 sing-box DNS 卡顿两案(均与本案无因果证据,但说明当晚机器有过扰动/重启,00:27 的启动很可能是其中一次重启)。

## 下次继续时的验证循环(一条命令定红绿)

1. 本地登录(勿走 RDP)→ 管理员 PowerShell:`Restart-Service Sunshine` → 看新日志 nvenc 探测段:绿=假设 1 成立,红=按上表 #2→#3→#4 逐个换变量。
2. 若假设 1 成立的防复发:服务改"自动(延迟启动)",或登录后计划任务重启服务(该机是免登录远程运维定位,见 [2026-09-12-2016-win11-ssh-frp](../2026-09-12-2016-win11-ssh-frp/),不能靠"开机必有人登录"兜底)。

## 经验(可复用指纹)

- **「所有编码器同错、连 software 也死」= 采集层问题,与编码器硬件无关**——不要顺着编码器名字去查。
- **tray 创建时间 vs 服务启动时间的差值 = 会话状态时间线证据**:tray 只在用户登录进会话后才创建,可反推启动时刻是否无人登录。
- Sunshine 编码器探测只在启动时跑一次,失败不重试——"重启服务"是第一反应动作。

## Notebook 同步决定

`~/Notebook/Sunshine-Moonlight-串流/05-故障模式诊断手册.md` 遵循「所有故障须有实证证据」而本案根因未验证,**暂不写入**;验证结案后在 05 速查表补 Win11 行(并把 Win11 宿主侧故障从 Linux 特定的排查路径里分节)。

## 后续修正(2026-09-14 09:5x,来自关机慢案的时间线解谜)

同日关机排查([2026-09-14-0953-win11-shutdown-wslservice-hang](../2026-09-14-0953-win11-shutdown-wslservice-hang/))实证:**当晚(00:27)机器根本没有重启**——那次"关机"被 WSLService 挂死拖了 60s 后转换失败,滑入 Modern Standby 整夜睡眠(Power-Troubleshooter:Sleep 00:27:25 → Wake 08:59:06),08:59 唤醒登录后 tray 才创建。故本案"00:27 服务全新启动"的真相是:关机转换中途 Sunshine 被停止后由 SCM 恢复策略拉起,探测失败于**转换/无会话状态**——假设 #1"无人登录时启动"方向正确、机制修正(不是开机自启时机问题,是关机转换态问题)。修复建议不变:登录后 `Restart-Service Sunshine` 验证;若"关机变睡眠"治好后再开机自启,探测应正常。

## 参考

- LizardByte/Sunshine 已知同类:#1293(远程 headless 启动)、#939(停用某屏后)、#3447(Win 24H2)、#260(指定 dGPU)
- 本机 Sunshine 装机档案:[2026-09-12-1330-sunshine-windows11-winnat](../2026-09-12-1330-sunshine-windows11-winnat/)

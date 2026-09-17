# Win11 电源设置恢复 09-14 前默认 + Intel 驱动日更后 USB 楔死复测

- 环境:Windows 11 **25H2 (26200.9457)** @ MECHREVO 耀世15 Pro 2024(GM5IX0A,i7-14650HX + RTX 4060,物理机 DESKTOP-J7NBNU4);诊断自 WSL2 Ubuntu 26.04 @ 同机经 powershell.exe 互操作完成。注意:09-14 档案时为 23H2 (22631),本周内已连升两级 feature update。

## 背景与问题

用户记忆"上次被改成 legacy 电源管理方式",要求"改回现代方式"。核查结论:**从未存在 legacy 化**——`powercfg /a` 实证睡眠一直是 Modern Standby(S0 Low Power Idle),固件仅支持它;用户实际记得的是 09-14 USB 楔死事故当天的缓解措施(关 USB 选择性暂停 + 禁快速启动,见 [2026-09-14-1130-usb-root-cause-research](../2026-09-14-1130-usb-root-cause-research/))。用户随后说明当日(09-17)经驱动精灵大量更新了 Intel 驱动,希望恢复默认设置并验证驱动更新是否消除了该问题。

## 当日驱动更新盘点(setupapi.dev.log + UserPnp 实证)

| 时间 | 内容 |
|---|---|
| 15:23–15:28 | Intel 芯片组 INF(PCIe Root Port 7A30 等 ~12 个系统设备) |
| 20:26 | 卸载 09-14 楔死幽灵端口残留(VID_0000&PID_0002 @ 5&551BC54&0&2/&3) |
| 20:32–20:56 | DTT(动态调优)、IPF CPU 框架、GNA、LPSS GPIO、RaptorLake PCH-S INF、HidEventFilter、Intel Wi-Fi(Netwtw08/6e);**hpygid19_v4.inf(HP 驱动,驱动精灵误推,存疑)** |
| 21:02–21:04 | Intel ME 接口(HECI/DAL/MEWMIProv)→ 21:04 重启生效 |

关键事实:**肇事栈未换**——TB4 控制器(DEV_1134)仍为 Intel 2023 v1.41.1379.0(oem43.inf),两枚 xHCI(DEV_1135/7A60)均为微软 inbox usbxhci.inf(10.0.26100.9444)。09-14 研究的根因(EC/BIOS 对 Maple Ridge D3cold 时序缺陷,BIOS EOL 无更新)不受这些更新影响,预期不乐观;但 DTT/ME 参与电源域协同,值得实测。

## 方案

1. 恢复 09-14 前默认:USB 选择性暂停 AC/DC → Enabled;快速启动(HiberbootEnabled)→ 1。这同时构成复现条件(缓解措施撤除)。
2. Modern Standby 唤醒实测(复现路径:待机 → 唤醒 → TB4 端口 Code 43?)。

## 验收标准

1. 选择性暂停 AC/DC=1、`powercfg /a` 重新列出 Fast Startup;
2. 唤醒后 `Get-PnpDevice` 在线 USB/HID 无 Status≠OK、无新增 VID_0000 幽灵(Code 43);
3. 真正的判定 = **过夜待机后晨间唤醒**(事故复现模式是 8.5h 长待机,非分钟级小睡)。

## 结果(2026-09-17 晚)

- 设置恢复完成(AC/DC=1、Fast Startup available、TB4/xHCI 栈 Status=OK 基线干净)。
- 首轮短测:21:23:03 睡 → 21:25:56 醒(2m53s),唤醒后全部在线 USB/HID OK;当日无 USBHUB3 196/205 仲裁事件——**DRIPS 危险窗口未打开,弱证据,不算通过**。
- 幽灵设备 5&551BC54&0&2/&3/&18 为 IsPresent=False 注册表残影(非在线),无害。
- **遗留验证:过夜待机 → 明晨先试外接键鼠再说话;若楔死复现 = 驱动更新无效,处置照旧(长按电源冷启动);若正常 = 驱动/feature update 可能生效,观察一周无复发可结案。**

## 风险

- hpygid19_v4.inf(HP 驱动)系驱动精灵误推装入了 MECHREVO 机器,建议下次清理驱动时移除并观察。
- 23H2→25H2 两级跳变本身改变了 USB/TB 栈行为(usbxhci 26100 分支),若楔死消失,归因可能是 feature update 而非驱动精灵装的 Intel 驱动——档案里两者分开记。

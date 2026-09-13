# Win11 外接键鼠集体失灵:设备端 MCU 挂死(重启无效,拔插断电才复位)

日期:2026-09-13 · 状态:已修复并双重验证(键盘换口恢复 + 接收器拔插恢复) · 流程:systematic-debugging skill(四阶段,先根因后修复)

- 环境:Windows 11 物理机 DESKTOP-J7NBNU4(笔记本,内置键鼠走 I2C HID/PS2);排查自 WSL2 Ubuntu 26.04 @ 同机(mirrored networking)经 powershell.exe 互操作完成;外设:NuPhy 有线 USB 键盘(VID_19F5&PID_1028)+ 罗技 Logi Bolt 接收器(VID_046D&PID_C547,LIGHTSPEED);USB 控制器:Intel xHCI VEN_8086&DEV_7A60(键鼠所在)+ DEV_1135

## 背景与症状

外接 USB 键盘与鼠标**同时**失灵(无输入),笔记本**内置**触控板和键盘正常。用户为修复做过一次完整重启(22:40),无效。用户怀疑与近期新装软件有关(前一日装过 libvirtualhid/ViGEmBus/Dokan/腾讯 Androws 等)。

## 范围

**In:** 定位外接键鼠失灵根因并修复。
**Out:** Logitech LampArray 服务创建 7 个虚拟 LIGHTSPEED Receiver 节点(现象记录在案,未证实有影响);NuPhy/罗技固件升级(预防性建议)。

## 根因(证据链)

**结论:两台设备的 MCU 因一次 USB 电气/信号扰动同时挂死——控制通道活着(枚举 OK)、中断输入不再发送。主机侧软硬件全部无罪。**

### 排除过程(Phase 1-2)

| 假设层 | 证据 | 结论 |
|---|---|---|
| 分流/软件全局拦截 | 内置键鼠正常,AutoHotkey 仅为自用 app 切换脚本 | 排除 |
| HID/键盘/鼠标类过滤驱动 | 注册表 Upper/LowerFilters 全部干净(kbdclass/mouhid/kbdhid/hidusb 标准) | 排除 |
| PnP/驱动栈 | Logi/NuPhy 全部节点 Status=OK、prob=0、mouhid/kbdhid 正常绑定 | Windows 视角设备"健康" |
| USB 总线/控制器 | 同一 xHCI(7A60)下 JBL USB-C 耳机正常出声;键鼠原口插 U盘正常识别弹窗 | 排除 |
| 设备本身坏 | 键盘换到另一口**立即恢复** | 设备没坏,是**挂死态** |

### 决定性证据(Phase 3)

1. **重启无效、拔插换口立即恢复**:重启(xHCI 完整重新枚举)**不消除端口的 VBUS 供电**——挂死的设备 MCU 保持供电、保持挂死;物理拔插才断电复位 MCU。
2. **扰动佐证**:Logi 接收器所在口位置(`5&551bc54&0&3`)早前出现过 `Unknown USB Device (Device Descriptor Request Failed)` 幽灵记录——该口经历过枚举级电气异常。
3. **同构恢复验证**:键盘换口恢复后,接收器拔插 3 秒回插,鼠标同样恢复——两设备同机理,根因链闭合。

### 内外设为何不同命

内置键盘/触控板走 I2C HID + PS/2(不经过 USB),外设走 USB 中断端点——扰动只打挂了 USB 设备端。

## 修复

物理拔插 3 秒(断 VBUS → MCU 复位)→ 两设备恢复。无需任何系统层改动。

## 验收标准与结果

| 标准 | 结果 |
|---|---|
| 键盘恢复 | 换口插上立即可用 ✓ |
| 鼠标恢复 | 接收器拔插 3 秒回插恢复 ✓ |
| 无系统层残留问题 | 类过滤干净、PnP 全 OK,未做任何系统变更 ✓ |

## 风险与后续

- **复发处置**:拔插 3 秒即可,**不要指望重启**(不断电,无效还浪费时间)。
- 复发频繁则:① NuPhy 官方工具升级键盘固件;② Logi Options+/G HUB 升级 Bolt 接收器固件;③ 接收器避开出过 descriptor failure 的那个口;④ 若固定某一口高发,该口硬件降级的嫌疑上升。
- 未解之谜(不追):今晚 22:40 重启无 1074 发起者记录(用户手动重启,日志缺失原因不明);LampArray 7 个虚拟节点的成因。

## 参考

- 关键命令:`Get-PnpDevice`/`Get-PnpDeviceProperty`(DEVPKEY_Device_IsPresent/ProblemCode/Parent/LocationInfo)、`Get-WinEvent`(System:Kernel-PnP 400/410/411/219、SCM 7045、Power-Troubleshooter)、注册表 `HKLM\SYSTEM\CCS\Control\Class\{*}` UpperFilters/LowerFilters
- 同日晚间的 sing-box DNS 排查档案:[2026-09-13-2219-singbox-bilibili-dns-stall](../2026-09-13-2219-singbox-bilibili-dns-stall/)(无关,仅同日)

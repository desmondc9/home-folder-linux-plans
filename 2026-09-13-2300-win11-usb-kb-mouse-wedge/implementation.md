# 实施记录:Win11 外接键鼠失灵排查(纯取证,零系统变更)

日期:2026-09-13 · 对应 [spec.md](./spec.md)

## 任务清单

- [x] Phase 1 取证:设备枚举(`Get-PnpDevice`)、问题码/在线状态、睡眠唤醒时间线、7 天服务安装史(7045)、Kernel-PnP 事件、USB 拓扑(parent 链向上走 6 层)
- [x] Phase 2 排除:类过滤驱动注册表扫描、kbdhid/mouhid/hidusb 绑定核查、可疑进程(AHK/libvirtualhid_broker/logi_lamparray)核查
- [x] Phase 3 判别:引导用户做三个物理测试(U盘/换口/JBL 旁证)+ 拔插复位验证,锁定设备端 MCU 挂死
- [x] Phase 4 修复:键盘换口 + 接收器拔插,双双恢复;清理 6 个临时调试脚本(`C:\Users\Desmond\Apps\usb-debug*.ps1`)

## 变更文件

| 位置 | 变更 |
|---|---|
| 无系统/驱动/注册表变更 | 修复=物理拔插断电复位 |
| `C:\Users\Desmond\Apps\usb-debug[1-6].ps1` | 排查期间临时脚本,事后已删除 |

## 验证方式

```powershell
# PnP 全链路状态 + 问题码(全部 OK/prob=0 → 软件栈无罪)
Get-PnpDevice -InstanceId 'HID\VID_046D&PID_C547&MI_00\7&3A9AC75&0&0000' | ft Status
(Get-PnpDeviceProperty -InstanceId <id> -KeyName 'DEVPKEY_Device_ProblemCode').Data
# 拓扑归属(确认键鼠与 U盘/JBL 同一 xHCI 控制器)
(Get-PnpDeviceProperty -InstanceId <id> -KeyName 'DEVPKEY_Device_Parent').Data
# 类过滤驱动(应仅 kbdclass/mouclass)
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96b-e325-11ce-bfc1-08002be10318}'
```

判别性物理测试(关键证据,远程拿不到):
1. U盘插键鼠原口 → 识别弹窗 = 端口活
2. NuPhy 换口 → 立即恢复 = 设备挂死而非损坏、系统无罪
3. JBL USB-C 耳机(同控制器)出声 = xHCI 数据面活
4. Logi Bolt 拔插 3 秒 → 鼠标恢复 = 与键盘同机理,链闭合

## 备注(可迁移经验)

1. **"重启无效、拔插有效"是设备端挂死的指纹**:重启不切除 USB 端口 VBUS,挂死 MCU 跨重启存活;只有物理断电能复位。USB 外设集体失灵时先拔插再谈其他。
2. **枚举 OK ≠ 输入活着**:PnP Status=OK 只证明控制通道(枚举/描述符)正常;输入走中断端点,设备固件挂死时 Windows 全然不知。判别靠"同口换设备、同设备换口"。
3. **内置键鼠(I2C HID/PS2)与 USB 外设天然分栈**:一半失灵=另一半的栈立即无罪,直接砍掉一半假设空间。
4. **注册表类过滤驱动是输入类故障的第一嫌疑人**:Keyboard/Mouse/HIDClass 的 UpperFilters 出现非 kbdclass/mouclass 项即为流氓软件指纹(本次干净,快速排除)。
5. **WSL 排查 Windows 的互操作套路**:`Get-PnpDevice`/`Get-WinEvent`/`Get-CimInstance` 全部可经 `powershell.exe -File` 跑;嵌套引号地狱用临时 .ps1 文件解决(zsh 里双引号会打架,脚本文件最稳);需要 admin 的操作走 `Start-Process -Verb RunAs`(会弹 UAC,`-Wait` 可能卡死别带)。
6. **设备位置指纹**:幽灵设备(Descriptor Request Failed)的 parent 位置串(`5&551bc54&0&3`)可与现役设备对照——同位置=同一物理口的历史异常,是判断"口不稳"的关键证据。

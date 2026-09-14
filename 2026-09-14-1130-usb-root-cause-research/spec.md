# Win11 外接 USB 失灵根因研究:锁定 Maple Ridge TB4 子系统电源域(固件层)

- 环境:Windows 11 23H2 (22631) @ MECHREVO 耀世15 Pro 2024(GM5IX0A 准系统,i7-14650HX + RTX 4060,物理机 DESKTOP-J7NBNU4,BIOS N.1.07MRO11/2024-05-21,仅 Modern Standby);诊断与调研自 WSL2 Ubuntu 26.04 @ 同机经 powershell.exe 互操作 + web 调研完成

## 背景与问题

今晨(2026-09-14 08:59)从 Modern Standby 唤醒后外接键鼠全灭(详见当日会话处置:冷启动修复 + 关 USB 选择性暂停 + 禁快速启动)。本文档回答用户的追问:**会不会是主板或某些驱动导致的?** —— 即对故障层(OS/驱动 vs 固件 vs 板级硬件)做信源级调研定位。

## 结论(证据与推测分层)

1. **出故障的 DEV_1135 不是 PCH 集成 xHCI,而是离散 Maple Ridge 雷电4控制器的 xHCI**(本地实证:同组 DEV_1134 设备名 "Thunderbolt(TM) Controller - 1134"、DEV_1133 PCIe Switch,SUBSYS 1F2=同方;pci.ids:8086:1135 = Maple Ridge 2C)。故障边界精确落在 TB4/USB-C 子系统这一个**固件管理的独立电源域**;正常的 DEV_7A60 是 PCH xHCI。
2. **驱动层排除**:Code 43「Device Descriptor Request Failed」发生在总线枚举阶段、任何设备驱动加载之前(CM_PROB_FAILED_POST_START 官方语义);微软 23H2 Release Health 2025-2026 无任何匹配的 USB 已知问题/KB;09-11 装的 Logitech oem33.inf 同理排除。
3. **根因排序:① EC/BIOS 对 Maple Ridge 子系统 DRIPS 退出时 D3cold 电源时序缺陷(最可能)——软件 disable/enable(≈D3hot)救不回、仅 POST 重新上电可复位正是 D3cold 级卡死表型(Dell Modern Standby 白皮书原理);Linux 内核对 Maple Ridge xHCI runtime PM 的专门怪癖史佐证该子系统 D3cold 历来依赖固件协同。② OS×固件交互残留可能(低)。③ 板级硬件(供电/PHY)最低——冷启 100% 恢复 + 周期性复发 + 同控制器端口 1 存活,更符合状态机卡死而非物理损伤。**

## 与 2026-09-13-2300-win11-usb-kb-mouse-wedge 的交叉证据

昨晚 23:00 事故(设备 MCU 楔死:枚举 OK 但中断停发,拔插断电即愈)与今晨事故(控制器端口楔死:Code 43 不枚举,仅冷启动可愈)是**同源 USB 扰动的两种落点**(扰动打挂下游设备 MCU 或打挂控制器端口状态机),12 小时内两次,均涉及同一组外设。注意:昨晚档案记录键鼠挂在 DEV_7A60,今晨实证在 DEV_1135 端口 2/3(设备换口所致或昨晚档案误记,存疑待下次发生时核对)。昨晚"关机"实际转为整夜 Modern Standby 睡眠(见 2026-09-14-0953-win11-shutdown-wslservice-hang),该睡眠周期正是今晨端口楔死的直接前置事件。

## 已落地处置(当日会话)

冷启动恢复 + 关闭 USB 选择性暂停(AC/DC)+ 禁用快速启动。BIOS 无公开更新(官网 API 全量核对 3649 条,2024 款已 EOL,人工渠道可问)。

## 验证路径(下次复发时)

1. 复发时先记录 `Get-PnpDevice` 端口态 + Thunderbolt 控制器(DEV_1134)电源状态,区分两种落点;
2. Linux live USB 下 suspend/resume 复测,彻底分离「固件层 vs Windows 层」;
3. 若频率上升或同控制器端口 1(hub/耳机链路)也开始死 → 板级硬件嫌疑上升,考虑返修。

详细信源(每条含 URL 与确证/传闻分级、未找到项如实记录)见 [research.md](./research.md)。

# 实施记录:Win11 电源设置恢复 + 驱动日更后 USB 楔死复测

日期:2026-09-17 · 对应 [spec.md](./spec.md)

## 任务清单

- [x] 核查"legacy 电源管理"记忆 → 不存在;实为 09-14 缓解措施(选择性暂停 OFF + 快速启动 OFF)
- [x] 盘点当日 Intel 驱动更新(setupapi.dev.log 分段时间线 + 在线驱动版本)
- [x] 恢复默认:选择性暂停 AC/DC=1 + HiberbootEnabled=1(提权 powercfg + 注册表)
- [x] 基线核查:TB4(DEV_1134)/xHCI(DEV_1135/7A60)全 Status=OK Problem=0
- [x] 首轮短时(2m53s)Modern Standby 唤醒实测:在线 USB/HID 全 OK,无 196/205(弱证据)
- [ ] **过夜待机晨间复测**(待明晨;用户先试外接键鼠,再跑下方验证命令)

## 变更清单

| 位置 | 变更 | 状态 |
|---|---|---|
| 电源计划 Balanced · USB settings | USB selective suspend AC/DC: 0(Disabled)→ 1(Enabled) | 已生效(powercfg /q 实证) |
| `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power` | HiberbootEnabled: 0 → 1 | 已生效(powercfg /a 重新列出 Fast Startup) |

系统其余零变更(仅读取事件日志/注册表/驱动版本)。当日驱动精灵/Intel 安装器的变更为用户自行操作,非本任务所做。

## 关键命令(复用)

```powershell
# 恢复(提权)
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1
powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1
powercfg /setactive SCHEME_CURRENT
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 1 -Type DWord

# 晨间验证(非提权)
Get-PnpDevice -PresentOnly | ? { $_.Class -in 'USB','HIDClass','Mouse','Keyboard' -and $_.Status -ne 'OK' }   # 应为空
Get-WinEvent -FilterHashtable @{LogName='System';StartTime=(Get-Date).Date} | ? { $_.Id -in 196,205 }        # USBHUB3 仲裁
Get-PnpDevice | ? { $_.InstanceId -match 'USB\\VID_0000' -and $_.Present }                                    # 在线幽灵 = 复现
```

## 备注(可迁移经验)

1. **"你上次帮我改成了 legacy"类记忆要先核档案再动手**:本次若盲改(如强设 S3/PlatformAoAcOverride)会制造真问题。`~/plans` 全文检索 + `powercfg /a` 现场实证双确认后,发现"legacy"实为事故缓解措施。
2. **提权脚本从 WSL 触发的稳定套路**:写 .ps1 到 `/mnt/c/.../Temp/`,`Start-Process powershell -Verb RunAs -ArgumentList -File ...`(不带 -Wait),脚本自身写日志到 `$env:TEMP\*.log`,事后从 `/mnt/c` 回读。UAC 弹窗需用户在物理屏确认。
3. **分钟级小睡 ≠ 有效复测**:Modern Standby 短睡不触发 USBHUB3 196/205(DRIPS USB 仲裁),复现窗口未打开;USB 楔死的判定周期是**过夜级长待机**,短测只能证明"没立刻坏"。
4. setupapi.dev.log(`/mnt/c/Windows/INF/setupapi.dev.log`)可从 WSL 直接 awk 解析,`Section start <日期>` 配对前置 `[Device Install...]` 行即可还原驱动安装时间线,比 Win32_PnPSignedDriver 可靠(后者 InstallDate 常为空)。
5. 驱动精灵会误推他牌驱动(hpygid19=HP)入机,已记录待清理。

# 实施记录: Sunshine 熄屏断连修复

日期: 2026-08-20 晚

## 任务清单

- [x] T1 定位根因: 日志证据链(sunshine.log / user journal / coredumpctl / powerdevilrc)→ DPMS 关屏致 KMS 枚举为空
- [x] T2 Fix A: `sd 'TurnOffDisplayIdleTimeoutSec=1800' 'TurnOffDisplayIdleTimeoutSec=0' ~/.config/powerdevilrc` + `systemctl --user restart plasma-powerdevil.service`;重启后复查值仍为 0 ✓
- [x] T3 Fix B 尝试: sunshine.conf 加 `global_prep_cmd`(SimulateUserActivity + kscreen-doctor --dpms on + sleep 2),重启后确认配置被解析 ✓
- [x] T4 单元验证唤醒命令本身: 手动 `kscreen-doctor --dpms off` → 执行 do 命令内容 → 双屏恢复 on ✓
- [x] T5 端到端实验: DPMS off 状态下 iPad 发起 Moonlight 连接
  - 精确复现下午故障(`Couldn't find monitor [0]` → Fatal → 500)—— 根因坐实 ✓
  - 同时证伪 Fix B: prep do-cmd 在编码器探测**之后**才执行(21:19:07.562 vs 探测 21:19:00),且引号被吞 exit code 2 ✗
- [x] T6 回退 Fix B: 从 sunshine.conf 移除 `global_prep_cmd`,重启服务,启动探测 `Found connector ID [140]` 正常 ✓
- [x] T7 归档本文档 + 更新记忆(sunshine-display-switch.md 追加 DPMS 教训)

## 变更的文件

| 文件 | 变更 | 状态 |
|------|------|------|
| `~/.config/powerdevilrc` | `[AC][Display] TurnOffDisplayIdleTimeoutSec` 1800→0 | 保留(修复) |
| `~/.config/sunshine/sunshine.conf` | 加后又删 `global_prep_cmd` | 已还原,无净变更 |

## 验证方式

- Fix A 配置持久性: 重启 powerdevil 后 `grep TurnOff ~/.config/powerdevilrc` = 0
- 故障机理: 手动 DPMS off 复现 500,屏幕回亮即恢复(见 design.md)
- 服务健康: 重启后启动探测成功、47990 UI 正常

## 未做(留待需要时)

- watchdog 增强 "DPMS off 自动唤醒"(见 design.md 残余风险)
- 真实 30 分钟闲置回归测试(机理已实证,价值低)

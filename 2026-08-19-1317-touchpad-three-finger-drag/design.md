# 触控板三指拖拽 (linux-3-finger-drag) 设计文档

日期:2026-08-19 · 状态:已完成,已验证 · 实施计划:[implementation.md](implementation.md)

## 背景与目标

在 Kubuntu 26.04(Plasma 6.6.4,Wayland)笔记本上实现 macOS 式**三指拖拽**:三指按住触控板移动,即拖动光标下的窗口/文字/图标,抬手结束。原装只有"点按-拖拽"(双击并按住)可用,长距离拖拽体验差。

## 范围

**In scope:**
- 三指按住 + 移动 = 拖拽(窗口/选区/图标)
- 拖拽锁定:抬手后 250ms 内再次三指按下可延续同一次拖拽(用户明确要求,长距离拖拽不用一口气划完)
- 不破坏既有手势:单指/双指照常,三指快速轻扫仍切虚拟桌面,三指点按仍是中键
- 开机自启,登录即生效

**Out of scope:**
- 其他手势的自定义(KWin 可配置手势 MR 未合入,等上游)
- 外接鼠标行为

## 现状分析

- **KDE 原生不支持**三指拖拽:三指手势硬编码用于虚拟桌面切换,无开关可关掉单侧三指绑定(kwin issue #18);可配置多指手势的 [MR !9598](https://invent.kde.org/plasma/kwin/-/merge_requests/9598) 未合入 → 纯"监听型"手势工具(如 touchegg/libinput-gestures)无法阻止 KWin 同时响应三指,方案必须**在 evdev 层截流**。
- 环境:触控板 `UNIW0001:00 093A:0255`(`i2c-hid`,`/dev/input/event6`);cargo 1.95.0 已装;用户已在 `input` 组;`/dev/uinput` 存在(root:input 0660);systemd user 会话。

## 方案设计

### 选型(3 个候选)

| 候选 | 结论 |
|---|---|
| 等 KDE 原生(MR !9598 及后续) | 时间不可控,弃 |
| [marsqing/libinput-three-finger-drag](https://github.com/marsqing/libinput-three-finger-drag) | Rust,133 stars,但实现较早期 | 
| **[lmr97/linux-3-finger-drag](https://github.com/lmr97/linux-3-finger-drag) v2.0.0**(采用) | Rust,120 stars,活跃维护(2026-08-09 仍有更新);**专为 Wayland/KDE 开发调试**;v2.0 是完整 evdev 多点触控代理 |

### 架构(引自上游 README,已实测验证)

```
真实触控板 ──(独占抓取)──> linux-3-finger-drag
                                │        │
                                │        ├──> 合成"克隆触控板"(非三指拖拽的一切
                                │        │     逐字节镜像;身份同名同 VID/PID,
                                │        │     KDE 的自然滚动/点按设置继续生效)
                             手势        │
                             状态机       └──> 虚拟鼠标(三指拖拽期间
                                               BTN_LEFT + 移动)
```

关键机制:未分类的触摸先扣留(单指 15ms / 2-3 指 50ms 判定窗口);恰好三指按住的触摸**合成器永远看不到**(KWin 无法对看不见的手指切桌面);其余手势(轻扫/点按/四指)原样转发。

### 关键决策

1. **不跑上游 `install.sh`,改用 README 手动步骤**——脚本结尾交互询问"是否立即重启",非交互执行时 EOF 命中默认值 y → **直接重启机器**。功能完全等价且可控。
2. `dragEndDelay = 250`(默认 0)——用户选择的拖拽锁定窗口。
3. 其余参数全默认(`acceleration=1.0`、`entryDebounce=50`、`probeDelay=15`、`pressGrace=75`)。
4. 服务绑定 `graphical-session.target`,`Restart=on-failure`(1s)——代理独占触控板,挂掉即触控板失灵,需秒级拉起兜底。

### 风险与缓解

| 风险 | 缓解 |
|---|---|
| 代理进程死亡 → 触控板失灵 | `Restart=on-failure` 1 秒拉起;进程退出即刻恢复直通 |
| 非交互跑 install.sh 会重启机器 | 已规避(手动安装),并写入 memory 防再犯 |
| 触控板驱动/固件行为差异 | 前台试跑 + 日志验证(实测一次通过) |
| 手感不合 | 配置热重载,`acceleration` 可随时调 |

## 验收标准(全部通过,2026-08-19 用户实测)

1. ✅ 三指按住移动 → 拖动窗口/选中文本
2. ✅ 抬手 250ms 内再按三指 → 延续同一次拖拽
3. ✅ 三指快速轻扫 → 切换虚拟桌面照常
4. ✅ 三指点按 → 中键
5. ✅ 单指移动/点按、双指滚动与之前完全一致
6. ✅ 服务 `systemctl --user` enabled + active,日志确认独占抓取 event6、克隆与虚拟鼠标设备已创建

## 参考资料

- 上游仓库与 README(安装/配置/排障):https://github.com/lmr97/linux-3-finger-drag
- KWin 可配置手势 MR:https://invent.kde.org/plasma/kwin/-/merge_requests/9598
- KDE 手势定制 mini-sprint(2025-06):https://blogs.kde.org/2025/06/12/gesture-customization-mini-sprint/
- 相关 memory:[touchpad-three-finger-drag](../../../../.claude/projects/-home-desmond/memory/touchpad-three-finger-drag.md)

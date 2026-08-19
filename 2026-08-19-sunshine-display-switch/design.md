# Sunshine 串流显示器切换脚本 — 设计

日期: 2026-08-19

## 背景与目标

本机(Kubuntu 26.04, Plasma Wayland, 独显直连 NVIDIA)有两个显示器,运行 Sunshine 串流服务(用户级 systemd 服务 `app-dev.lizardbyte.app.Sunshine.service`)。人在外面通过 SSH (`laptop.signal-align.com`) 登录时,需要能用一条命令切换 Sunshine 捕获哪块屏。

## 现状分析

- Sunshine 配置: `~/.config/sunshine/sunshine.conf`,关键项 `output_name`,仅在启动时读取 → 改配置必须重启服务。
- 显示器:
  - `eDP-1` = 笔记本内屏 (BOE), DRM connector_id **140**
  - `HDMI-A-1` = 小米外接屏, DRM connector_id **137**
  - 两个接口都挂在 `/dev/dri/card1` (nvidia-drm) 上 —— 本机是独显直连,不存在 iGPU/dGPU 分卡问题。

## 关键坑(实测确认)

1. **本机 Sunshine 版本 2026.516.143833 的 KMS 后端 `output_name` 只支持数字序号**。
   上游 master 已有"connector 名 → 序号"映射(`map_display_name_to_monitor_index`),
   但该版本没有:`util::from_view("eDP-1")` 解析失败产生乱码序号,报
   `Couldn't find monitor [553171]`,所有编码器探测失败 → 串流完全不可用。**必须写数字。**
2. **日志里 "Monitor N is XXX" 列表的顺序会在重启间翻转**,不代表真实捕获顺序,不可用于映射。
3. **真实捕获结果看 `Found connector ID [N]`**: 启动时编码器探测会触发一次捕获初始化。
   实测(plane 枚举顺序): `output_name=0` → connector 140 (eDP-1); `output_name=1` → connector 137 (HDMI-A-1)。
4. 连续重启会触发 systemd 用户服务限流 (`start of the service was attempted too often`),
   需要 `reset-failed` 后重试。

## 方案

脚本 `~/.local/bin/sunshine-display`(已在 PATH):

- `sunshine-display` — 显示当前配置
- `sunshine-display 0|1` — 切换到指定屏(0=内屏, 1=外接屏)
- `sunshine-display toggle` — 来回切换

流程: 改 `output_name` → `reset-failed` + 重启服务(限流则等 10s 重试) → 等 6s →
从 journal 核对 `Found connector ID` 是否与预期一致(不一致则告警,防止枚举顺序变化后切错屏)。

副作用: 重启 Sunshine 会断开当前串流,Moonlight 客户端需重连。可接受 —— 本来就是远程操作场景。

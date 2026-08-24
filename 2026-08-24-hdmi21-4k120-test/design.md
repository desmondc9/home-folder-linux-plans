# 换 HDMI 2.1 满血线后外接屏 4K@120 验证

日期:2026-08-24

## 背景

2026-08-21 外接小米 4K 屏在 4K@160 下随机 FRL link-training 失败(黑屏闪断,怀疑线缆),已降级 4K@60 规避。2026-08-24 更换"满血版 HDMI 2.1"线缆(48G),验证链路能否稳定跑 HDMI 2.1 FRL,并将外接屏设为 4K@120。

## 验证链路三要素(2026-08-24 实测)

| 环节 | 证据 | 结论 |
|------|------|------|
| GPU 出口 | `/sys/class/drm/card1` driver→nvidia,PCI 10DE:28A0(RTX 4060 Laptop);eDP-1 与 HDMI-A-1 均在 card1 上 | HDMI 口直连 RTX 4060(Ada,HDMI 2.1b FRL6 48G);Intel 核显不在此显示路径 |
| 显示器 | EDID(`edid-decode`):XMI Mi Monitor,HDMI Forum VSDB:SCDC Present、Max FRL 12 Gbps/lane × 4 lanes = 48G(FRL6)、DSC 1.2a、VIC 117/118(4K@100/120) | 显示器完整支持 HDMI 2.1 |
| 线缆 | 4K@160(4:2:0 8bit ≈ 19.2G)超 TMDS 18G 上限,且 DSC 仅随 FRL 存在 → 能点亮 160 即 FRL;60 秒压测 link=connected、dpms=on 零断链(旧线正是在此频率闪黑) | 新线确跑 FRL;60s 无事件但长期稳定性待观察 |

## 决定性判据(为什么 160Hz 是 FRL 实锤)

- TMDS(HDMI 2.0 及以下)最大 18 Gbps:4K@160 最低编码(4:2:0 8bit,~1400-1600MHz 像素时钟 × 12bit)≈ 19.2G,塞不进。
- DSC 压缩传输是 HDMI 2.1 FRL 专属特性。
- 故 4K@160 出图 ⇒ 链路必为 FRL。4K@120 RGB(≈28.5G)同理超 TMDS,日常即跑在 FRL 上。

## 结果

- 最终设定:`kscreen-doctor output.HDMI-A-1.mode.6` → 3840x2160@119.88,dpms on,链路稳定。
- KDE 会按连接记忆持久保持该模式。

## 遗留 / 建议

- [ ] 观察一两天是否有随机黑屏闪断(旧故障为随机性,60s 干净 ≠ 长期证明);重点覆盖 Sunshine 串流时段。
- [ ] 若稳定,可考虑常驻 4K@160(新线已通过 60s 压测)或开启 HDR/10bit(EDID 支持 SMPTE ST2084)。
- [ ] 若再闪黑:先降 100/120Hz 区分线缆余量问题 vs 端口硬件问题;Sunshine watchdog 的 DPMS 自愈仍可用。

# Phase 1: Hardware configuration for Wine

Delivered as reusable tooling in `~/.local/bin/` (each app prefix applies it),
rather than a single base prefix.

## Deliverables

- `~/.local/bin/wine-app-env.sh` — sourceable env: iGPU pin, fcitx IME, zh_CN.UTF-8, XWayland
- `~/.local/bin/wine-nvidia-env.sh` — opt-in NVIDIA dGPU offload
- `~/.local/bin/configure-wine-prefix.sh <PREFIX> [DPI]` — DPI + font smoothing + CJK substitution

## Tasks

- [x] HiDPI: `configure-wine-prefix.sh` sets `LogPixels` (default **132** ≈137%)
- [x] Fonts: subpixel RGB smoothing via registry
- [x] CJK: link Noto Sans/Serif CJK + WQY into prefix; map YaHei/SimSun/宋体/黑体 → Noto Sans CJK SC
- [x] XWayland: Wine uses x11 driver under KDE XWayland (native Wayland driver avoided)
- [x] NVIDIA: opt-in PRIME-offload wrapper created
- [x] iGPU pin verified working
- [ ] Multi-monitor placement: verify with a real app (done in Phase 2)

## Notes / results

- **Display setup:** eDP-1 2560×1600@240 (scale 1.35, primary) + HDMI-A-1 4K
  (scale 1.5). Mixed scaling — Wine uses one global DPI (132 chosen); tune per
  use by re-running `configure-wine-prefix.sh <prefix> <dpi>` or via `winecfg`.
- **GPU pin verified:** `glxinfo` under the env → `Mesa Intel(R) Graphics (RPL-S)`.
  Without the env, system default GL device is the NVIDIA 4060. So pinning the
  iGPU is a real stability win for 2D desktop apps.
- **Cosmetic warning:** `libEGL ... 10de:28a0 driver (null)` still prints — mesa
  enumerating the NVIDIA render node. Selected renderer is still Intel. Launchers
  filter these lines from logs.
- **fcitx:** wired via `XMODIFIERS=@im=fcitx` (Wine consumes fcitx over XIM).

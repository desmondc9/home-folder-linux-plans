# Design: Latest Wine + Windows WeChat/Teams on Kubuntu 26.04

**Date:** 2026-07-01
**Machine:** Kubuntu 26.04 LTS (resolute), KDE Plasma, Wayland
**Hardware:** Intel Raptor Lake iGPU + NVIDIA RTX 4060 Mobile (hybrid, open driver 595.71.05)

## Goal

Install the latest Wine natively (via apt / WineHQ) and configure it for this
hardware so the user can run Windows `.exe` software. Named targets: the
**Windows** builds of WeChat (微信) and Microsoft Teams, ideally with
video/audio calls, camera, and in-call remote control.

The user explicitly chose to run the **Windows .exe** versions under Wine, with
honest expectations set (see "Reality check" below), even though native Linux
clients for both apps are already installed on this machine.

## Starting state (verified 2026-07-01)

- Wine: **not** installed via dpkg/apt; no `wine` binary in PATH.
- WineHQ resolute repo exists; latest = `winehq-staging` **11.12**; stable = 11.0.
- Ubuntu `universe` has `wine` 10.0 (fallback only).
- `i386` foreign architecture already enabled.
- Bottles flatpak already installed (not used here — user wants native apt Wine).
- Native Linux WeChat already installed: `wechat 4.1.1.4` (Tencent, `/opt/wechat`).
- `teams-for-linux` flatpak already installed.

## Key decisions

- **Wine build:** WineHQ `winehq-staging` 11.12 (native apt). Staging carries the
  most compatibility patches — best chance for complex apps like WeChat.
- **winetricks:** install latest from upstream (Ubuntu's packaged version lags and
  breaks verbs).
- **Prefix strategy:** one dedicated 64-bit `WINEPREFIX` per app, kept under
  `~/.local/share/wineprefixes/`. No Bottles (user wants native apt Wine).
- **Display server path:** run Wine apps through **XWayland** (the default on KDE
  Wayland). Wine 11's native Wayland driver is still experimental and less
  compatible for these GUI apps.
- **GPU:** default to the Intel iGPU for these apps (more stable). Provide an
  optional NVIDIA PRIME-offload launcher wrapper for apps that want the dGPU.

## Reality check (honest expectations)

- **Camera under Wine:** Wine has no reliable v4l2 webcam support. Video calls
  needing the camera are expected to fail.
- **WeChat Windows calls:** voice/video calls under Wine are historically broken;
  messaging / moments / file transfer usually work.
- **New Teams:** WebView2/Edge-based; very likely will not run under Wine at all.
  Will be attempted and the result documented, not promised.
- **In-call remote control:** downstream of calls working; inherits the above risk.
- Where the Windows-under-Wine path fails, the already-installed native Linux
  WeChat and `teams-for-linux` remain the practical answer for calls/camera.

## Phases

- **Phase 0** — Install Wine + winetricks, verify. (`implementations/phase-0-install-wine.md`)
- **Phase 1** — Hardware config: HiDPI, CJK fonts, XWayland, NVIDIA PRIME, multi-monitor. (`implementations/phase-1-hardware-config.md`)
- **Phase 2** — Windows WeChat prefix. (`implementations/phase-2-wechat.md`)
- **Phase 3** — Windows Teams prefix (attempt). (`implementations/phase-3-teams.md`)
- **Phase 4** — Camera / audio / in-call remote-control test + document. (`implementations/phase-4-calls-camera-remote.md`)

Phases 0–1 are reliable wins. Phases 2–4 are best-effort against Wine's known
limitations, with results documented honestly.

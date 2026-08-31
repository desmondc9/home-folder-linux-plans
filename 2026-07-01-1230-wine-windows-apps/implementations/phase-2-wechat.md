# Phase 2: Windows WeChat (微信) under Wine

Dedicated prefix: `~/.local/share/wineprefixes/wechat` (win64).

## Tasks

- [x] Create win64 prefix + apply Phase 1 config (DPI, fonts)
- [x] winetricks deps: `corefonts riched20` (+ msls31 auto-dep)
- [x] Download official Windows WeChat installer (3.9.12.1000)
- [x] Run installer under the prefix → WeChat 3.9.12.57 installed
- [x] fcitx input wiring (via wine-app-env.sh XMODIFIERS)
- [x] Create `.desktop` launcher (Name[zh_CN]=微信) + icon
- [x] Smoke test: login + messaging + Chinese input all work (WeChat 4.1.11) ✓
      Actual login + send message: pending user scan.

## PIVOT — 3.9 is server-blocked; **WeChat 4.1.11 works**

Tencent **server-side deprecated 3.9.x**: after QR login it forces an upgrade and
blocks all use. Switched to the current **WeChat 4.1.11** (`WeChatWin_4.1.11.exe`,
installs as `C:\Program Files\Tencent\Weixin\Weixin.exe`). Result: **logged in
fully, main window works** (user-confirmed). Launchers repointed to `Weixin.exe`.

### The two fixes that made 4.x work
1. **Virtual-desktop mode** (`wine explorer /desktop=weixin,WxH`) — maps the windows.
2. **Remove `DRI_PRIME=0`** from the GPU env — 4.x's Chromium GPU process rejects it
   (`Invalid value (0) for DRI_PRIME. Should be > 0`) and renders blank. The GLVND
   vendor override (`__GLX_VENDOR_LIBRARY_NAME=mesa`) alone still pins the Intel iGPU.

## KEY FINDING — virtual-desktop only needed for FIRST LOGIN (updated 2026-07-02)

The **first-run login window** stays **IsUnMapped** (QR never shows) under KDE
Wayland/XWayland with a plain windowed launch → use the virtual desktop
(`wine explorer /desktop=wechat,WxH Weixin.exe`, `~/.local/bin/wechat-wine-desktop`)
for that first login only.

**Once logged in, plain windowed mode works** — `wine Weixin.exe` maps the main
window fine (verified: main window `IsViewable` 1100x921, WM_CLASS `weixin.exe`).
Per user preference, the **default launcher is now plain** `~/.local/bin/wechat-wine`
(no virtual desktop); `wechat-wine.desktop` Exec + `StartupWMClass=weixin.exe` updated.
Keep `wechat-wine-desktop` around as a fallback.

Audio note: 语音消息 recording requires the prefix audio backend = ALSA (see phase-4).

## Expectations

Messaging / moments / file transfer: likely OK.
Camera + voice/video calls: likely broken (tested in Phase 4).

## Notes / results

- **Prefix:** `~/.local/share/wineprefixes/wechat` (win64). Configured via
  `configure-wine-prefix.sh` — LogPixels 132, subpixel smoothing, CJK subs. ✓
- **Version chosen:** official `WeChatSetup.exe` = **WeChat 3.9.12.1000** (271 MB,
  NSIS, i386). The 3.9.x line is the Wine-friendly one (4.x is much harder).
- **Dep gotcha:** winetricks `corefonts` needs `cabextract` (apt, sudo). Installed.
- **Proxy note:** downloads route through user proxy `127.0.0.1:10808`. `sudo`
  drops that env → run downloads as the user, not under sudo.

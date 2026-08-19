# Phase 4: Calls / camera / in-call remote control — test & document

## Tasks

- [ ] Confirm camera devices (`/dev/video*`) and whether Wine can enumerate them
- [x] Test audio in/out inside WeChat-under-Wine (PulseAudio/PipeWire routing)
      → 语音消息 (按住说话) recording FIXED by switching prefix audio backend to ALSA
        (winepulse rejects WeChat's malformed 2ch/mask-0x4 capture format). See notes.
- [ ] Test a voice call, then a video call, in WeChat-under-Wine
- [ ] Test in-call remote control (only if a call connects)
- [ ] Record what works vs. fails, with the concrete error/behavior
- [ ] Where Wine fails, document the native-Linux alternative that works

## Notes / results

### Audio driver layer — VERIFIED WORKING (2026-07-02)

Investigated "WeChat 语音输入不能使用". First hypothesis was a **defective WineHQ
`11.12~resolute-1` package** because the on-disk tree has `winepulse.so`/`winealsa.so`
(unix) but **no PE `winepulse.drv`/`winealsa.drv`/`wineoss.drv` stubs** (confirmed:
`dpkg-deb -c` on the .deb; noble/jammy builds also omit the standalone PE .drv).

**That hypothesis was DISPROVEN by runtime trace** (`WINEDEBUG=+mmdevapi` while
launching Weixin.exe). Wine loads the audio backend as a **builtin** — the PE side
is synthesized from the `.so`, the standalone `.drv` file is not needed:

```
mmdevapi:load_driver Successfully loaded L"winepulse.drv" with priority Preferred
mmdevapi:load_driver Successfully loaded L"winealsa.drv" with priority Neutral
mmdevapi:init_driver Selecting driver L"pulse" with priority Preferred
get_device_name_from_guid Found matching device key
    L"1,alsa_input.pci-0000_00_1f.3.analog-stereo"   ← the mic, enumerated
```

So playback + capture devices enumerate correctly. **Audio driver layer is NOT the
root cause.** Host stack: PipeWire 1.6.2 + pipewire-pulse; default source =
`alsa_input.pci-0000_00_1f.3.analog-stereo`.

### ROOT CAUSE + FIX — 语音输入 (按住说话) — RESOLVED (2026-07-02)

Symptom (user-confirmed): pressing 按住说话 → toast **"unable to record audio,
try again later"**. Host mic itself is fine (`parecord` captures at max 0 dB).

Trace at the moment of recording (`WINEDEBUG=+winepulse,+mmdevapi`) — WeChat's
capture `client_Initialize` requests a `WAVEFORMATEXTENSIBLE`:
`nChannels=2`, `wBitsPerSample=16`, **`dwChannelMask=0x00000004`** (SPEAKER_FRONT_
CENTER — a single-channel bit). Wine's **winepulse** enforces
`popcount(mask) == nChannels` (1 ≠ 2) and bails:

```
err:pulse:pulse_spec_from_waveformat Invalid channel mask: 1/2 and 4(4)
err:pulse:pulse_spec_from_waveformat Invalid format! Channel spec valid: 0, format: 3
```

→ capture stream never opens → "unable to record audio". Windows and Wine's
**winealsa** are lenient about this malformed mask; only winepulse is strict.

**FIX (applied):** switch this prefix's audio backend from pulse to ALSA:
```
WINEPREFIX=~/.local/share/wineprefixes/wechat \
  wine reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d alsa /f
```
ALSA routes to PipeWire via the alsa-pipewire plugin (`/etc/alsa/conf.d/50-pipewire.conf`,
`libasound_module_pcm_pipewire.so`). After the switch mmdevapi selects `winealsa.drv`,
the "Invalid channel mask" error is gone, and **按住说话 recording works** (user-confirmed).

Note: this was NOT the earlier missing-`winepulse.drv` red herring — Wine loads the
audio backend as a builtin regardless of the standalone PE `.drv` file.

### Launcher: plain windowed is now the default (no virtual desktop)

Once logged in, plain `wine Weixin.exe` maps the main window fine
(`xwininfo`: main window `IsViewable` 1100x921; WM_CLASS `weixin.exe`). The
virtual-desktop workaround was only needed for the first-run **login** window under
KDE Wayland. Default launcher switched back to `~/.local/bin/wechat-wine` (plain);
`wechat-wine.desktop` Exec + `StartupWMClass=weixin.exe` updated. `wechat-wine-desktop`
kept as a fallback if a future first-login window fails to map.

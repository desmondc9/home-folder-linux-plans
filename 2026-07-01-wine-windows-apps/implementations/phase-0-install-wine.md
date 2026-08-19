# Phase 0: Install WineHQ staging 11.12 + winetricks

## Tasks

- [x] Add WineHQ repo key (dearmored) to `/etc/apt/keyrings/winehq-archive.gpg`
- [x] Add WineHQ resolute sources (`/etc/apt/sources.list.d/winehq.sources`)
- [x] `apt update`
- [x] `apt install --install-recommends winehq-staging` (11.12) ✓
- [x] Install latest `winetricks` 20260125-next (jsDelivr) to `/usr/local/bin` ✓
- [x] Verify `wine --version` == `wine-11.12 (Staging)` ✓
- [x] Boot a throwaway base prefix to confirm Wine runs ✓

## Notes / results

- **Wine installed:** `wine-11.12 (Staging)`; dpkg `winehq-staging` + `wine-staging`
  `11.12~resolute-1`. Latest WineHQ build for Ubuntu 26.04.
- **Gotcha 1 — armored key rejected:** apt refuses an ASCII-armored key saved as
  `.key` ("unsupported filetype"). Fix: `gpg --dearmor` → `winehq-archive.gpg`.
- **Gotcha 2 — USTC pool not synced:** `mirrors.ustc.edu.cn/wine-builds` has the
  metadata index but 404s on the `.deb` pool. Switched repo to TUNA mirror.
- **Gotcha 3 — no i386 build:** WineHQ resolute publishes amd64 only. Fine —
  Wine 11 new-WoW64 runs 32-bit Windows apps without a separate i386 package.
- **Gotcha 4 — winetricks download hangs:** `raw.githubusercontent.com` is
  GFW-throttled; pull winetricks from jsDelivr / ghfast instead.

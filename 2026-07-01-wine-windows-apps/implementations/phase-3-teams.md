# Phase 3: Windows Microsoft Teams under Wine (best-effort)

Dedicated prefix: `~/.local/share/wineprefixes/teams` (win64).

## Tasks

- [x] Create win64 prefix + Phase 1 config
- [x] Attempt: new Teams (MSIX/WebView2) — **FAILED** (documented below)
- [~] Fallback: classic Teams — SKIPPED (EOL, sign-in blocked since 2024, so it
      could never reach a meeting even if it launched)
- [x] If neither runs: document and point to native `teams-for-linux` (installed as
      Flatpak `com.github.IsmaelMartinez.teams_for_linux` 2.11.1)

## Expectations

New Teams is WebView2/Edge-based and very likely will not run under Wine.
This phase documents the actual outcome rather than promising success.

## Notes / results — new Teams under Wine FAILED (2026-07-02)

Prefix: `~/.local/share/wineprefixes/teams` (win64, Phase-1 config). WebView2
Evergreen runtime installed OK via `winetricks -q webview2` (msedgewebview2.exe
149.0.4022.98 present). Artifacts pulled via proxy from `statics.teams.cdn.office.net`:
`teamsbootstrapper.exe` (2 MB) + `MSTeams-x64.msix` (261 MB, contains ms-teams.exe 34 MB).

Two install paths, both dead-end:

1. **Bootstrapper provisioning** — `wine teamsbootstrapper.exe -p -o <MSTeams-x64.msix>`:
   ```json
   { "success": false, "errorCode": "0x80004001" }   // E_NOTIMPL
   ```
   Wine ships `appxdeploymentclient.dll` + `dism.exe` but they are **stubs** — MSIX/AppX
   provisioning is not implemented, so the package can't be registered.

2. **Extract MSIX + run ms-teams.exe directly** (bypasses AppX): process starts, spawns
   a WebView2 child, but **never renders a window and exits**. Teams' own launcher log
   (`AppData\Local\Microsoft\MSTeams\Logs\Launcher_*.log`):
   ```
   wWinMain: Starting process_type: ''
   WIL: ms-teams.exe ... LogHr(1) 80040154
   WIL: ms-teams.exe ... LogHr(2) 80040154
   ```
   `0x80040154 = REGDB_E_CLASSNOTREG`. The launcher needs COM classes that only get
   registered during proper MSIX provisioning (the AppxManifest's COM/app-identity
   registrations) — which Wine can't do (see path 1). Forcing software rendering
   (`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu --no-sandbox ...`) did NOT
   help — it dies at COM class registration, before any rendering.

**Conclusion:** new Teams cannot run under Wine on this box. Root chain:
MSIX provisioning stubbed (E_NOTIMPL) → required COM classes unregistered →
launcher aborts (REGDB_E_CLASSNOTREG). Classic Teams is EOL (sign-in blocked), so
it's not a viable fallback for reaching a meeting.

### Share desktop + remote control — not reachable via Wine (see phase-4)

Even if Teams launched, the two requested features are blocked by architecture, not
just by this crash:
- **Screen share:** a Wine/XWayland app on KDE Wayland can only capture its own
  surfaces, not the host screen (Wayland security). Real capture needs
  xdg-desktop-portal + PipeWire, which a Wine app can't use.
- **Remote control (grant control):** the remote party would inject input into the
  host desktop; Wine can only inject into its sandboxed Windows env, never the host —
  architecturally impossible.

**Recommendation:** use native `teams-for-linux` for meetings/screen-share. Its
remote-control (give/take control) support is limited (community Electron wrapper);
Wayland screen-share works via the portal.

Cleanup note: the `teams` prefix (~1.5 GB with WebView2 + extracted Teams) can be
removed with `rm -rf ~/.local/share/wineprefixes/teams` if not keeping this evidence.

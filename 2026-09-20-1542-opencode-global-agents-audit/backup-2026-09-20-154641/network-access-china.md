# Network access from mainland China

> Moved into a standalone reference document on 2026-09-12 for progressive disclosure; `~/.config/opencode/AGENTS.md` points to this file. Battle-tested knowledge — edit carefully, as the port history below reflects real debugging incidents.

I am based in mainland China. Some resources (Docker Hub, PyPI, uv, npm, Maven, Gradle, GitHub, Huggingface, GCP/Google Cloud Console, Google APIs and documentation, etc.) may be slow, time out, or be unreachable directly due to GFW restrictions.

**Google/GCP domains are a special case — set the proxy proactively, before the first request, not reactively after a failure.** Requests to `*.google.com`, `*.googleapis.com`, `console.cloud.google.com`, Google/GCP docs, etc. — via WebFetch or any other tool — don't fail fast under the GFW; they hang until the tool's own timeout, which looks like the tool itself being stuck rather than a network issue. Export the proxy env vars (below) before fetching any Google/GCP URL, don't wait for the hang to happen first.

For everything else, if you hit connection failures, slow downloads, or timeouts when accessing such resources, choose the best fix instead of just retrying:

1. **Prefer a domestic mirror first** when one exists for the tool (e.g. Aliyun PyPI mirror, npmmirror registry, Aliyun/USTC Docker registry mirrors, Aliyun Maven mirror). Mirrors are faster and don't depend on the proxy being up.

if uv is slow, add the pypi mirror into pyproject.toml to speed up package installation, for example:

  ```toml
  [tool.uv]
  index-url = "https://mirrors.aliyun.com/pypi/simple/"
  extra-index-url = ["https://pypi.org/simple"]
  ```

if npm is slow, you can set the registry to a mirror to speed up package installation: `https://registry.npmmirror.com`

Use `https://` for both mirrors — verified 2026-08-30: the Aliyun index over plain `http://` hangs until timeout (which `uv`/`pip` hit on every run, since they fetch the index root), and `http://registry.npmmirror.com` just 301s to HTTPS anyway.

2. **Fall back to the local proxy** when no good mirror exists or the mirror itself fails (e.g. GitHub, Docker Hub image pulls, Google/GCP resources — see above, arbitrary web resources). Export before running the command:

   ```bash
   export http_proxy=http://127.0.0.1:10809
   export https_proxy=http://127.0.0.1:10809
   export all_proxy=socks5://127.0.0.1:10809

   export HTTP_PROXY=http://127.0.0.1:10809
   export HTTPS_PROXY=http://127.0.0.1:10809
   export ALL_PROXY=socks5://127.0.0.1:10809
   ```

   **10809 is a mixed inbound — it speaks both HTTP CONNECT and SOCKS5, so `socks5://…:10809` above is correct, not a typo.** On this machine (WSL2 @ the Windows 11 desktop, mirrored networking), the listener is the **Windows host's sing-box service** (`C:\Users\Desmond\Apps\sing-box\config.json`, inbound `mixed-in` on `127.0.0.1:10809`); mirrored mode shares loopback, so WSL reaches it at `127.0.0.1:10809`. **10808 was v2rayN's xray, retired 2026-09-12 — nothing listens there anymore** (the old "nothing on 10808, verified with `ss -ltn`" claim was true for the Kubuntu laptop, not here). Don't "correct" these to 10808: a doc that assumed the wrong port once cost a debugging cycle, because `gcloud` reacts to an unreachable proxy by claiming the credentials are expired. To check the proxy from WSL, `ss -ltn` is useless — the listener sits on the host and is invisible to WSL — so test with `curl -x http://127.0.0.1:10809 https://api.ipify.org` (expect the VPS IP 104.194.83.82) or `/mnt/c/Windows/System32/netstat.exe -ano | grep 10809`. Note the host also runs sing-box in TUN mode, so ordinary WSL egress is already split-routed (国内直连/国外走 VPS) — the explicit env vars above are only needed to force a proxy leg for a specific command. The sing-box service's CN DNS upstream is AliDNS **DoH** `https://223.5.5.5/dns-query` (`type: https`, not bare UDP:53 — switched 2026-09-13 after bare-UDP exchanges stalled 7-10s/timeouted intermittently, which froze bilibili video buffering because its CDN domains have ~10s TTLs; config backup `config.json.bak-20260913-alidns-doh`).

3. For tools that ignore env proxy vars (e.g. some Docker daemons, systemd services), configure their proxy settings explicitly (e.g. `~/.docker/config.json`, `/etc/systemd/system/docker.service.d/http-proxy.conf`) rather than giving up.
4. If both a mirror and the proxy fail, diagnose (check whether the local proxy at `127.0.0.1:10809` is actually running) before concluding the resource is unreachable.

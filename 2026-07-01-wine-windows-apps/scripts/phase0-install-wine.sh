#!/usr/bin/env bash
# Phase 0: Install WineHQ staging (latest, 11.12) + winetricks on Kubuntu 26.04 (resolute)
# Run with: sudo bash phase0-install-wine.sh
set -euo pipefail

echo "==> [1/6] Enable i386 multiarch (idempotent)"
dpkg --add-architecture i386 || true

echo "==> [2/6] Add WineHQ signing key (dearmored — apt rejects armored .key files)"
install -d -m 0755 /etc/apt/keyrings
# Key is small; fetch from upstream (mirror key files can lag).
# Modern apt requires a binary keyring OR a .asc extension for Signed-By;
# an armored key saved as .key is rejected as "unsupported filetype".
curl -fsSL --retry 3 https://dl.winehq.org/wine-builds/winehq.key \
  | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.gpg
chmod 0644 /etc/apt/keyrings/winehq-archive.gpg
# Remove the old armored file if a previous run left it behind
rm -f /etc/apt/keyrings/winehq-archive.key

echo "==> [3/6] Add WineHQ resolute repo (TUNA mirror — USTC pool/ is not synced, 404s on debs)"
# NOTE: USTC mirrors the metadata but NOT the .deb pool for wine-builds (verified 2026-07-01).
# TUNA has both index and binaries, and is fast in CN. amd64 only: WineHQ resolute publishes
# no i386 packages — Wine 11 uses new-WoW64 so 32-bit Windows apps work without an i386 build.
cat > /etc/apt/sources.list.d/winehq.sources <<'EOF'
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/wine-builds/ubuntu/
Suites: resolute
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/winehq-archive.gpg
EOF

echo "==> [4/6] apt update"
apt-get update

echo "==> [5/6] Install winehq-staging (latest available = 11.12)"
DEBIAN_FRONTEND=noninteractive apt-get install -y --install-recommends winehq-staging

echo "==> [6/6] Install latest winetricks (CN-accessible mirrors; raw.githubusercontent is GFW-throttled)"
wt=/usr/local/bin/winetricks
if   curl -fsSL --max-time 60 -o "$wt" "https://cdn.jsdelivr.net/gh/Winetricks/winetricks@master/src/winetricks"; then
  echo "    winetricks via jsDelivr"
elif curl -fsSL --max-time 60 -o "$wt" "https://ghfast.top/https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks"; then
  echo "    winetricks via ghfast proxy"
else
  echo "    upstream mirrors failed; falling back to apt winetricks"
  DEBIAN_FRONTEND=noninteractive apt-get install -y winetricks
  wt=$(command -v winetricks)
fi
chmod +x "$wt" 2>/dev/null || true

echo
echo "==================== VERIFY ===================="
echo "wine:       $(command -v wine || echo MISSING)"
echo "wine ver:   $(wine --version 2>/dev/null || echo FAILED)"
echo "wine64 ver: $(wine64 --version 2>/dev/null || echo 'n/a (unified in wine 11)')"
echo "winetricks: $(winetricks --version 2>/dev/null | head -1 || echo FAILED)"
echo "================================================"
echo "Phase 0 done. Next: Phase 1 (hardware config) runs as your normal user (no sudo)."

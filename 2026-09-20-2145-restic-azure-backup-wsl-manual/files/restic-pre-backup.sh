#!/usr/bin/env bash
# 备份前钩子:刷新 manifests + 打捞被排除工具链里的小配置。root 运行。
set -euo pipefail
DEST=/home/desmond/Backups
M="$DEST/manifests"; D="$DEST/dotfiles"
mkdir -p "$M" "$D"
rm -rf "$M"; mkdir -p "$M"

{ echo "# generated $(date -Is) on $(hostname)"; uname -a; /usr/local/bin/restic version; } > "$M/system-info.txt"
apt-mark showmanual          > "$M/apt-mark-showmanual.txt"
dpkg --get-selections        > "$M/dpkg-selections.txt"
command -v snap >/dev/null 2>&1 && snap list > "$M/snap-list.txt" || true
command -v flatpak >/dev/null 2>&1 && flatpak list > "$M/flatpak-list.txt" || true
command -v podman   >/dev/null 2>&1 && podman images > "$M/podman-images-root.txt" || true
runuser -u desmond -- podman images > "$M/podman-images-desmond.txt" 2>/dev/null || true
runuser -u desmond -- bash -lc 'command -v code >/dev/null 2>&1 && code --list-extensions' > "$M/code-extensions.txt" 2>/dev/null || true
ls /opt > "$M/opt-listing.txt"
chown -R desmond:desmond "$M"

salvage() {  # $1 = 绝对路径,存在则拷入 dotfiles 保持相对路径
  if [ -f "$1" ]; then
    mkdir -p "$D/$(dirname "${1#/}")"
    cp -a "$1" "$D/${1#/}"
    echo "salvaged: $1"
  fi
}
salvage /home/desmond/.m2/settings.xml
salvage /home/desmond/.cargo/config.toml
salvage /home/desmond/.cargo/credentials
salvage /home/desmond/.cargo/credentials.toml
salvage /home/desmond/.gradle/gradle.properties
salvage /home/desmond/.sdkman/etc/config
salvage /home/desmond/.android/adbkey
salvage /home/desmond/.android/adbkey.pub
salvage /home/desmond/.android/debug.keystore
salvage /home/desmond/.dotnet/NuGet/NuGet.Config
salvage /home/desmond/.nuget/NuGet/NuGet.Config
chown -R desmond:desmond "$D" 2>/dev/null || true
exit 0

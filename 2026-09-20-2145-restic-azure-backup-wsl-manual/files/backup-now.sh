#!/usr/bin/env bash
# 手动触发一次 restic 备份(走 systemd service,与母方案同代码路径;本机无 timer,仅手动)
set -euo pipefail
if command -v wsl.exe >/dev/null 2>&1 && wsl.exe -u root -- systemctl start --no-block restic-backup.service 2>/dev/null; then
  :
else
  sudo systemctl start --no-block restic-backup.service
fi
echo "started; tail with: journalctl -u restic-backup.service -f"

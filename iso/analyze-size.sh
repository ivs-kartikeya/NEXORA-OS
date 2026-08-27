#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${NEXORA_ISO_WORK:-$ROOT/.iso-work}"
CHROOT="$WORK/chroot"

if [[ ! -d "$CHROOT" ]]; then
  echo "No live-build chroot found at: $CHROOT" >&2
  echo "Build beta.3 once, then run this script." >&2
  exit 2
fi

echo "Nexora ISO size report"
echo "======================"
echo
printf 'Top-level chroot directories:\n'
sudo du -x -BM --max-depth=1 "$CHROOT" 2>/dev/null | sort -n | tail -25

echo
printf 'Largest individual files in the live root:\n'
sudo find "$CHROOT" -xdev -type f -printf '%s %p\n' 2>/dev/null \
  | sort -nr | head -40 \
  | awk '{ bytes=$1; $1=""; printf "%8.1f MiB %s\n", bytes/1048576, substr($0,2) }'

echo
printf 'Largest installed packages (KiB, from dpkg status):\n'
sudo chroot "$CHROOT" dpkg-query -W -f='${Installed-Size}\t${Package}\n' 2>/dev/null \
  | sort -nr | head -40 || true

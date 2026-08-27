#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -x "$ROOT/build-out/nexora-shell" && -x "$ROOT/build-out/nexora-core" ]] || "$ROOT/scripts/build.sh"

mkdir -p "$HOME/.local/bin" "$HOME/.local/libexec" "$HOME/.local/share/nexora"
install -m0755 "$ROOT/build-out/nexora-shell" "$HOME/.local/bin/nexora-shell"
install -m0755 "$ROOT/session/nexora-shell-supervisor" "$HOME/.local/libexec/nexora-shell-supervisor"

cat > "$HOME/.local/share/nexora/release" <<'REL'
NAME=Nexora OS
VERSION=1.0.1-beta.1
CHANNEL=public-beta
BASE=Debian-Linux
DESKTOP=Nexora
CORE_API=org.nexora.Core
AI=Tony
REL

sudo install -m0755 "$ROOT/session/start-nexora" /usr/local/bin/start-nexora
sudo install -d -m0755 /usr/share/wayland-sessions
sudo install -m0644 "$ROOT/session/nexora.desktop" /usr/share/wayland-sessions/nexora.desktop

BRIDGE_SRC="$ROOT/kwin/nexora-window-bridge"
BRIDGE_DST="$HOME/.local/share/kwin/scripts/nexora-window-bridge"
mkdir -p "$HOME/.local/share/kwin/scripts"
rm -rf "$BRIDGE_DST"
cp -a "$BRIDGE_SRC" "$BRIDGE_DST"
if command -v kwriteconfig6 >/dev/null 2>&1; then
  kwriteconfig6 --file kwinrc --group Plugins --key nexora-window-bridgeEnabled true
  kwriteconfig6 --file kwinrc --group Plugins --key engineeringos-window-bridgeEnabled false || true
fi
rm -rf "$HOME/.local/share/kwin/scripts/engineeringos-window-bridge" 2>/dev/null || true

"$ROOT/scripts/install-user-service.sh"

# Retire the old session only after the new session is fully installed.
sudo rm -f /usr/share/wayland-sessions/engineeringos.desktop /usr/local/bin/start-engineeringos
rm -f "$HOME/.local/bin/engineeringos-shell"

echo
echo "Nexora OS V1 Public Beta native session installed."
echo "Run ./scripts/doctor.sh before logging out."

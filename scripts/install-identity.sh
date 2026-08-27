#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME=/usr/share/sddm/themes/nexora
CONF=/etc/sddm.conf.d/90-nexora-theme.conf
sudo rm -rf "$THEME"
sudo install -d -m0755 "$THEME" /etc/sddm.conf.d
sudo cp -a "$ROOT/identity/sddm-nexora/." "$THEME/"
printf '[Theme]\nCurrent=nexora\n' | sudo tee "$CONF" >/dev/null
# Retire old prototype identity if present.
sudo rm -f /etc/sddm.conf.d/90-engineeringos-theme.conf
sudo rm -rf /usr/share/sddm/themes/engineeringos 2>/dev/null || true
echo "Nexora login identity installed. It takes effect on the next SDDM restart/login."

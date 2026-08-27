#!/usr/bin/env bash
set -euo pipefail
sudo rm -f /etc/sddm.conf.d/90-nexora-theme.conf
sudo rm -rf /usr/share/sddm/themes/nexora
echo "Nexora SDDM identity removed."

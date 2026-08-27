#!/usr/bin/env bash
set -euo pipefail
for svc in nexora-tony.service nexora-context.service nexora-core.service nexora-llm.service; do
  systemctl --user disable --now "$svc" >/dev/null 2>&1 || true
done
rm -f "$HOME/.local/bin/nexora-shell" "$HOME/.local/bin/nexora-core" "$HOME/.local/libexec/nexora-shell-supervisor"
rm -rf "$HOME/.local/share/kwin/scripts/nexora-window-bridge"
rm -f "$HOME/.config/systemd/user"/nexora-{core,context,tony,llm}.service
systemctl --user daemon-reload
sudo rm -f /usr/local/bin/start-nexora /usr/share/wayland-sessions/nexora.desktop
echo "Nexora session removed. User projects, Tony memory and model cache were left untouched."

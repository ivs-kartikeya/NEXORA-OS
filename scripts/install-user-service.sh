#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/.local/share/nexora/services"
BIN="$HOME/.local/share/nexora/bin"
mkdir -p "$DEST" "$BIN" "$HOME/.local/bin" "$HOME/.config/systemd/user" "$HOME/.config/nexora"

[[ -x "$ROOT/build-out/nexora-core" ]] || "$ROOT/scripts/build.sh"
install -m755 "$ROOT/build-out/nexora-core" "$HOME/.local/bin/nexora-core"
install -m755 "$ROOT/services/nexora-contextd.py" "$DEST/nexora-contextd.py"
install -m755 "$ROOT/services/tonyd.py" "$DEST/tonyd.py"
install -m755 "$ROOT/services/nexora-voiced.py" "$DEST/nexora-voiced.py"
install -m755 "$ROOT/runtime/run-tony-llm" "$BIN/run-tony-llm"
for unit in nexora-core.service nexora-context.service nexora-tony.service nexora-llm.service nexora-voice.service; do
  install -m644 "$ROOT/services/$unit" "$HOME/.config/systemd/user/$unit"
done

systemctl --user daemon-reload
systemctl --user enable nexora-core.service nexora-context.service nexora-tony.service nexora-voice.service >/dev/null
systemctl --user enable --now nexora-core.service nexora-context.service nexora-tony.service nexora-voice.service
# The model remains demand-loaded by Tony. Do not pay the RAM cost at login.
systemctl --user disable nexora-llm.service >/dev/null 2>&1 || true

echo "Nexora Core + Context + Tony + Voice services installed."

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -x "$ROOT/build-out/nexora-shell" ]] || "$ROOT/scripts/build.sh"
export QT_QPA_PLATFORM=wayland
exec dbus-run-session -- kwin_wayland --xwayland --exit-with-session "$ROOT/build-out/nexora-shell"

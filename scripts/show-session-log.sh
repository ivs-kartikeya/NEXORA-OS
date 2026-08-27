#!/usr/bin/env bash
set -euo pipefail
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/nexora/native-session.log"
if [[ -f "$LOG" ]]; then cat "$LOG"; else echo "No Nexora session log yet: $LOG"; fi

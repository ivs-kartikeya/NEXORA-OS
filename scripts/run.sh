#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/build-out/nexora-shell"
[[ -x "$BIN" ]] || "$ROOT/scripts/build.sh"
exec "$BIN"

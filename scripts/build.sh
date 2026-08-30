#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Keep every compiled component aligned with the single VERSION file. This
# prevents a future release from exposing stale beta/version strings.
"$ROOT/scripts/sync-version.sh" --apply

cmake -S "$ROOT" -B "$ROOT/build-out" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build "$ROOT/build-out" -j"$(nproc)"
echo "Built:"
echo "  $ROOT/build-out/nexora-shell"
echo "  $ROOT/build-out/nexora-core"

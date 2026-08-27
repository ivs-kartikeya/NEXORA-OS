#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cmake -S "$ROOT" -B "$ROOT/build-out" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build "$ROOT/build-out" -j"$(nproc)"
echo "Built:"
echo "  $ROOT/build-out/nexora-shell"
echo "  $ROOT/build-out/nexora-core"

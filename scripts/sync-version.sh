#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9._-]+)?$ ]] || {
  echo "Invalid VERSION: $VERSION" >&2
  exit 2
}
BASE_VERSION="${VERSION%%-*}"
MODE="${1:---apply}"

python3 - "$MODE" "$VERSION" "$BASE_VERSION" <<'PY'
from pathlib import Path
import re, sys

mode, version, base = sys.argv[1:4]
if mode not in {"--apply", "--check"}:
    raise SystemExit("usage: sync-version.sh [--apply|--check]")

rules = {
    "src/systembackend.h": [
        (r'QString osVersion\(\) const \{ return QStringLiteral\("[^"]+"\); \}',
         f'QString osVersion() const {{ return QStringLiteral("{version}"); }}'),
    ],
    "src/coredaemon.cpp": [
        (r'nexora-core/[0-9A-Za-z._-]+', f'nexora-core/{version}'),
        (r'\{QStringLiteral\("version"\), QStringLiteral\("[^"]+"\)\}',
         f'{{QStringLiteral("version"), QStringLiteral("{version}")}}'),
    ],
    "services/tonyd.py": [
        (r'\b\d+\.\d+\.\d+-beta\.\d+\b', version),
    ],
    "services/nexora-voiced.py": [
        (r'\b\d+\.\d+\.\d+-beta\.\d+\b', version),
    ],
    "kwin/nexora-window-bridge/metadata.json": [
        (r'"Version"\s*:\s*"[^"]+"', f'"Version": "{version}"'),
    ],
    "CMakeLists.txt": [
        (r'project\(NexoraOS VERSION [0-9.]+ LANGUAGES CXX\)',
         f'project(NexoraOS VERSION {base} LANGUAGES CXX)'),
    ],
    "session/start-nexora": [
        (r'(# Nexora OS native Wayland session entry point\.\n)(?:NEXORA_RELEASE="[^"]+"\n)?',
         rf'\1NEXORA_RELEASE="{version}"\n'),
    ],
    "iso/build-iso.sh": [
        (r'ISO_NAME="NexoraOS-[0-9A-Za-z._-]+-amd64\.iso"',
         f'ISO_NAME="NexoraOS-{version}-amd64.iso"'),
        (r'(?m)^VERSION=[0-9A-Za-z._-]+$', f'VERSION={version}'),
    ],
}

changed = []
for name, replacements in rules.items():
    p = Path(name)
    if not p.exists():
        raise SystemExit(f"version sync target missing: {name}")
    old = p.read_text()
    new = old
    for pattern, repl in replacements:
        new, count = re.subn(pattern, repl, new)
        if count == 0:
            raise SystemExit(f"version sync pattern missing in {name}: {pattern}")
    if new != old:
        changed.append(name)
        if mode == "--apply":
            p.write_text(new)

if mode == "--check" and changed:
    print("Version metadata is not synchronized:")
    for name in changed:
        print(f"  {name}")
    raise SystemExit(1)

if changed:
    print(f"Synchronized Nexora version {version} in {len(changed)} file(s).")
else:
    print(f"Nexora version metadata already synchronized: {version}")
PY

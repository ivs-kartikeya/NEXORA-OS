#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9._-]+)?$ ]] || {
  echo "  [FAIL] invalid VERSION: $VERSION" >&2
  exit 1
}

echo "Nexora OS $VERSION static audit"
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile services/nexora-contextd.py services/tonyd.py services/nexora-voiced.py
rm -rf services/__pycache__
echo "  [OK] Python services compile"

for f in scripts/*.sh session/start-nexora session/nexora-shell-supervisor runtime/run-tony-llm iso/build-iso.sh; do
  bash -n "$f"
done
echo "  [OK] shell scripts parse"

python3 - <<'PY'
import json,re
from collections import Counter
from pathlib import Path
json.loads(Path('kwin/nexora-window-bridge/metadata.json').read_text())
s=Path('qml/Main.qml').read_text()
ids=re.findall(r'\bid\s*:\s*([A-Za-z_][A-Za-z0-9_]*)',s)
dups=[k for k,v in Counter(ids).items() if v>1]
if dups: raise SystemExit('duplicate QML ids: '+', '.join(dups))
out=[]; i=0; quote=None; esc=False
while i<len(s):
    c=s[i]
    if quote:
        if esc: esc=False
        elif c=='\\': esc=True
        elif c==quote: quote=None
        out.append(' '); i+=1; continue
    if c in ('"', "'"):
        quote=c; out.append(' '); i+=1; continue
    if c=='/' and i+1<len(s) and s[i+1]=='/':
        while i<len(s) and s[i]!='\n': out.append(' '); i+=1
        continue
    out.append(c); i+=1
clean=''.join(out)
for a,b in [('{','}'),('(',')'),('[',']')]:
    if clean.count(a)!=clean.count(b): raise SystemExit(f'unbalanced QML {a}{b}')
for needle in ['function toggleDesktop()', 'function toggleTony()', 'systemBackend.toggleVoiceListening()', 'Ctrl+Space', 'Ctrl+Alt+T', 'Nexora Console']:
    if needle not in s: raise SystemExit('missing V1 QML hook: '+needle)
if 'Super  Space' in s or 'Super ⇧ Space' in s or 'Meta+Space' in s:
    raise SystemExit('old Super/Meta user-facing shortcut remains')
print(f'  [OK] QML structural audit ({len(ids)} ids)')
PY

if grep -q 'waitForFinished' src/systembackend.cpp; then
  echo "  [FAIL] blocking waitForFinished reintroduced into shell backend" >&2
  exit 1
fi
grep -q 'forkpty' src/systembackend.cpp
if grep -q 'QOverload<QSocketDescriptor, QSocketNotifier::Type>::of(&QSocketNotifier::activated)' src/systembackend.cpp; then
  echo "  [FAIL] Qt 6.8-incompatible QSocketNotifier overload reintroduced" >&2
  exit 1
fi
if grep -q 'QChar::Backspace' src/systembackend.cpp; then
  echo "  [FAIL] non-existent QChar::Backspace reintroduced" >&2
  exit 1
fi
grep -q 'terminalSessionReady' src/systembackend.h
grep -q 'voiceRequestBusy' src/systembackend.cpp
grep -q '%h/.local/share/nexora/services/nexora-voiced.py' services/nexora-voice.service
if grep -q '%h/.local/lib/nexora/services/nexora-voiced.py' services/nexora-voice.service; then
  echo "  [FAIL] old Voice daemon path reintroduced" >&2
  exit 1
fi
echo "  [OK] PTY console + Voice path/state guards present"

NEXORA_VERSION="$VERSION" python3 - <<'PY'
import json
import os
import re
from pathlib import Path

version = os.environ['NEXORA_VERSION']

checks = {
    'src/systembackend.h': version,
    'src/coredaemon.cpp': version,
    'services/tonyd.py': version,
    'services/nexora-voiced.py': version,
    'session/start-nexora': version,
    'iso/build-iso.sh': version,
}
for fn, needle in checks.items():
    text = Path(fn).read_text()
    if needle not in text:
        raise SystemExit(f'version mismatch in {fn}: expected {version}')

metadata = json.loads(Path('kwin/nexora-window-bridge/metadata.json').read_text())
metadata_version = str(metadata.get('KPlugin', metadata).get('Version', ''))
if metadata_version and metadata_version != version:
    raise SystemExit(f'version mismatch in kwin metadata: {metadata_version} != {version}')

iso = Path('iso/build-iso.sh').read_text()
expected_iso = f'NexoraOS-{version}-amd64.iso'
if expected_iso not in iso:
    raise SystemExit(f'ISO filename is not version coherent: expected {expected_iso}')

for fn in ['src/main.cpp','src/systembackend.cpp','src/systembackend.h','src/core_main.cpp','src/coredaemon.cpp','src/coredaemon.h']:
    text=Path(fn).read_text()
    if text.count('{') != text.count('}'):
        raise SystemExit(f'unbalanced C++ braces: {fn}')

# Reject any stale beta release marker, independent of the current release
# family. This keeps the audit valid when Nexora moves past 1.0.1.
release_files = list(checks) + ['kwin/nexora-window-bridge/metadata.json']
version_pattern = re.compile(r'\b\d+\.\d+\.\d+-beta\.\d+\b')
for fn in release_files:
    for found in version_pattern.findall(Path(fn).read_text()):
        if found != version:
            raise SystemExit(f'stale release version in {fn}: {found} (current {version})')

print(f'  [OK] release coherence for {version} + C++ structural smoke test')
PY

if grep -RIn -E 'engineeringos|EngineeringOSProjects|EngineeringOSNotes' src qml services runtime session kwin identity --exclude-dir=history >/tmp/nexora-stale-runtime 2>/dev/null; then
  echo "  [FAIL] stale EngineeringOS runtime namespace:" >&2
  cat /tmp/nexora-stale-runtime >&2
  exit 1
fi

echo "STATIC AUDIT PASSED"

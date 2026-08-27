#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="${1:-$ROOT/dist/NexoraOS-1.0.1-beta.1-amd64.iso}"
TAG="${NEXORA_TAG:-v1.0.1-beta.1}"

command -v gh >/dev/null 2>&1 || {
  echo "GitHub CLI (gh) is required. Install it, then run: gh auth login" >&2
  exit 2
}
[[ -s "$ISO" ]] || { echo "ISO not found: $ISO" >&2; echo "Build it first: ./iso/build-iso.sh" >&2; exit 2; }
SIZE=$(stat -c %s "$ISO")
LIMIT=$((2*1024*1024*1024))
if (( SIZE >= LIMIT )); then
  echo "ISO is >= 2 GiB and cannot be one GitHub Release asset. Build a smaller image first." >&2
  exit 3
fi
SHA="$ISO.sha256"
[[ -s "$SHA" ]] || sha256sum "$ISO" > "$SHA"

gh auth status >/dev/null
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG exists; uploading/replacing assets..."
  gh release upload "$TAG" "$ISO" "$SHA" --clobber
else
  gh release create "$TAG" "$ISO" "$SHA" \
    --prerelease \
    --title "Nexora OS V1 Public Beta" \
    --notes-file "$ROOT/RELEASE_NOTES.md"
fi

echo "Published $TAG. Do not commit the ISO into normal Git history."

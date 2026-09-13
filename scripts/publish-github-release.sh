#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9._-]+)?$ ]] || {
  echo "Invalid VERSION: $VERSION" >&2
  exit 2
}

ISO="${1:-$ROOT/dist/NexoraOS-${VERSION}-amd64.iso}"
TAG="${NEXORA_TAG:-v${VERSION}}"
EXPECTED_TAG="v${VERSION}"

command -v gh >/dev/null 2>&1 || {
  echo "GitHub CLI (gh) is required. Install it, then run: gh auth login" >&2
  exit 2
}
command -v sha256sum >/dev/null 2>&1 || {
  echo "sha256sum is required." >&2
  exit 2
}

if [[ "$TAG" != "$EXPECTED_TAG" ]]; then
  echo "Refusing release: tag $TAG does not match VERSION $VERSION (expected $EXPECTED_TAG)." >&2
  exit 2
fi

[[ -s "$ISO" ]] || {
  echo "ISO not found: $ISO" >&2
  echo "Build and validate it first with the Nexora ISO smoke workflow." >&2
  exit 2
}

EXPECTED_ISO="NexoraOS-${VERSION}-amd64.iso"
if [[ "$(basename "$ISO")" != "$EXPECTED_ISO" ]]; then
  echo "Refusing release: ISO filename must be $EXPECTED_ISO." >&2
  exit 2
fi

SIZE="$(stat -c %s "$ISO")"
LIMIT=$((2*1024*1024*1024))
if (( SIZE >= LIMIT )); then
  echo "ISO is >= 2 GiB and cannot be one GitHub Release asset. Build a smaller image first." >&2
  exit 3
fi

SHA="$ISO.sha256"
[[ -s "$SHA" ]] || {
  echo "Checksum file missing: $SHA" >&2
  echo "Publishing never creates release checksums; use the validated build output." >&2
  exit 4
}
(
  cd "$(dirname "$ISO")"
  sha256sum -c "$(basename "$SHA")"
)

gh auth status >/dev/null
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Refusing to modify existing release $TAG. Previous Nexora releases and assets are immutable by policy." >&2
  exit 5
fi

[[ -s "$ROOT/RELEASE_NOTES.md" ]] || {
  echo "RELEASE_NOTES.md is missing or empty." >&2
  exit 6
}

gh release create "$TAG" "$ISO" "$SHA" \
  --prerelease \
  --title "Nexora OS $VERSION" \
  --notes-file "$ROOT/RELEASE_NOTES.md"

echo "Published new release $TAG. Existing releases were not modified."

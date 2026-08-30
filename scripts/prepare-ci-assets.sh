#!/usr/bin/env bash
set -euo pipefail

DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nexora"
VOICE="$DATA/voice"
MODELS="$DATA/models"
LLAMA_SRC="$DATA/llama.cpp"
WHISPER_SRC="$VOICE/whisper.cpp"
WHISPER_MODELS="$VOICE/models"

# Pin the inference engines near the known-good beta.5 build window. CI must
# never silently build a release against whichever upstream commit happens to
# be newest that day.
LLAMA_REV="ca3d5a3e10d53f7ea672cb9b6178faca3e2807bc"
WHISPER_REV="978113305b2ead22249b881deafa131dc8884911"

QWEN_FILE="$MODELS/Qwen3-0.6B-Q4_0.gguf"
QWEN_URL="https://huggingface.co/ggml-org/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_0.gguf?download=true"
QWEN_SHA256="da2572f16c06133561ce56accaa822216f2391ef4d37fba427801cd6736417d4"

WHISPER_FILE="$WHISPER_MODELS/ggml-base.en.bin"
WHISPER_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin?download=true"
WHISPER_SHA256="a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"

mkdir -p "$MODELS" "$WHISPER_MODELS"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 2; }; }
for cmd in git curl sha256sum; do need "$cmd"; done

checkout_pinned() {
  local url="$1" dest="$2" rev="$3"
  if [[ ! -d "$dest/.git" ]]; then
    rm -rf "$dest"
    git clone --filter=blob:none --no-checkout "$url" "$dest"
  fi
  git -C "$dest" fetch --depth 1 origin "$rev"
  git -C "$dest" checkout --detach --force FETCH_HEAD
  git -C "$dest" clean -ffdqx
  local got
  got="$(git -C "$dest" rev-parse HEAD)"
  [[ "$got" == "$rev" ]] || { echo "Pinned checkout mismatch for $dest: $got != $rev" >&2; exit 3; }
}

download_verified() {
  local url="$1" file="$2" expected="$3"
  if [[ -s "$file" ]]; then
    local cached
    cached="$(sha256sum "$file" | awk '{print $1}')"
    if [[ "$cached" == "$expected" ]]; then
      echo "Verified cached asset: $(basename "$file")"
      return 0
    fi
    echo "Discarding cached asset with unexpected digest: $file" >&2
    rm -f "$file"
  fi

  local tmp="$file.part"
  rm -f "$tmp"
  curl -fL --retry 4 --retry-delay 2 --connect-timeout 30 --progress-bar "$url" -o "$tmp"
  local actual
  actual="$(sha256sum "$tmp" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || {
    echo "Checksum mismatch for $(basename "$file")" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    rm -f "$tmp"
    exit 4
  }
  mv "$tmp" "$file"
  echo "Downloaded and verified: $(basename "$file")"
}

checkout_pinned "https://github.com/ggml-org/llama.cpp.git" "$LLAMA_SRC" "$LLAMA_REV"
checkout_pinned "https://github.com/ggml-org/whisper.cpp.git" "$WHISPER_SRC" "$WHISPER_REV"
download_verified "$QWEN_URL" "$QWEN_FILE" "$QWEN_SHA256"
download_verified "$WHISPER_URL" "$WHISPER_FILE" "$WHISPER_SHA256"

echo "CI/release inference assets are pinned and verified."

#!/usr/bin/env bash
set -euo pipefail
PROFILE="${1:-fast}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nexora"
SRC="$DATA/llama.cpp"
MODELS="$DATA/models"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/nexora/tony.env"
mkdir -p "$DATA" "$MODELS" "$(dirname "$CONF")"

case "$PROFILE" in
  fast|lite)
    MODEL_FILE="$MODELS/Qwen3-0.6B-Q4_0.gguf"
    MODEL_URL="https://huggingface.co/ggml-org/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_0.gguf?download=true"
    CTX=3072
    MAX_TOKENS=320
    ;;
  quality|standard)
    MODEL_FILE="$MODELS/Qwen3-1.7B-Q4_K_M.gguf"
    MODEL_URL="https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf?download=true"
    CTX=4096
    MAX_TOKENS=420
    ;;
  *) echo "Usage: $0 [fast|quality]"; exit 2 ;;
esac

if [[ ! -d "$SRC/.git" ]]; then
  echo "Cloning llama.cpp (one-time)..."
  git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$SRC"
else
  echo "Updating llama.cpp..."
  git -C "$SRC" pull --ff-only || true
fi

cmake -S "$SRC" -B "$SRC/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DLLAMA_CURL=ON
cmake --build "$SRC/build" --target llama-server -j"$(nproc)"

if [[ ! -s "$MODEL_FILE" ]]; then
  echo "Downloading Tony $PROFILE model..."
  tmp="$MODEL_FILE.part"
  rm -f "$tmp"
  curl -L --fail --retry 4 --retry-delay 2 --progress-bar "$MODEL_URL" -o "$tmp"
  mv "$tmp" "$MODEL_FILE"
else
  echo "Tony model already cached locally: $MODEL_FILE"
fi

THREADS=$(nproc 2>/dev/null || echo 4)
(( THREADS > 6 )) && THREADS=6
(( THREADS < 2 )) && THREADS=2
BATCH_THREADS=$THREADS

cat > "$CONF" <<EOC
TONY_MODEL_FILE=$MODEL_FILE
TONY_MODEL_PROFILE=$PROFILE
TONY_CONTEXT=$CTX
TONY_THREADS=$THREADS
TONY_BATCH_THREADS=$BATCH_THREADS
TONY_LLAMA_PORT=8081
TONY_MAX_TOKENS=$MAX_TOKENS
TONY_MODEL_POLICY=balanced
TONY_BALANCED_IDLE_SECONDS=480
TONY_ECO_IDLE_SECONDS=75
EOC

systemctl --user daemon-reload
systemctl --user stop nexora-llm.service >/dev/null 2>&1 || true
# Start once to prove the local model loads. Tony can unload it after idle.
systemctl --user start nexora-llm.service

echo
echo "Tony $PROFILE profile configured."
echo "Model: $MODEL_FILE"
echo "Watch startup: journalctl --user -u nexora-llm.service -f"

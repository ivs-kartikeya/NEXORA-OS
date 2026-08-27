#!/usr/bin/env bash
set -u

VOICE_ROOT="$HOME/.local/share/nexora/voice"
WHISPER_DIR="$VOICE_ROOT/whisper.cpp"
MODEL_DIR="$VOICE_ROOT/models"
MODEL="$MODEL_DIR/ggml-base.en.bin"
PIPER_VENV="$VOICE_ROOT/piper-venv"
PIPER_VOICES="$VOICE_ROOT/piper-voices"
mkdir -p "$VOICE_ROOT" "$MODEL_DIR" "$PIPER_VOICES"

echo "Nexora Voice V1 repair/setup"
echo "Everything is local. No API keys or cloud speech services are used."

if command -v sudo >/dev/null 2>&1; then
  echo "[1/4] Installing local audio/speech dependencies..."
  sudo apt update
  sudo apt install -y git cmake build-essential curl python3 python3-venv python3-pip \
    espeak-ng pipewire-bin pulseaudio-utils alsa-utils ffmpeg ca-certificates || {
      echo "WARNING: one or more optional audio packages could not be installed."
    }
else
  echo "WARNING: sudo unavailable; assuming dependencies are already installed."
fi

if [ ! -x "$WHISPER_DIR/build/bin/whisper-cli" ]; then
  echo "[2/4] Building whisper.cpp..."
  if [ ! -d "$WHISPER_DIR/.git" ]; then
    rm -rf "$WHISPER_DIR"
    git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR" || true
  fi
  if [ -f "$WHISPER_DIR/CMakeLists.txt" ]; then
    cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" -DCMAKE_BUILD_TYPE=Release \
      -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF >/dev/null 2>&1 || true
    cmake --build "$WHISPER_DIR/build" --config Release -j"$(nproc 2>/dev/null || echo 4)" --target whisper-cli || true
  fi
else
  echo "[2/4] whisper.cpp already built."
fi

if [ ! -s "$MODEL" ]; then
  echo "[3/4] Downloading Whisper base.en (~142 MB)..."
  tmp="$MODEL.part"
  rm -f "$tmp"
  curl -L --fail --retry 3 --progress-bar \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin?download=true" \
    -o "$tmp" && mv "$tmp" "$MODEL" || rm -f "$tmp"
else
  echo "[3/4] Whisper model already present."
fi

# Natural TTS is optional. The OS always keeps espeak-ng as a small fallback,
# but Piper gives Tony a much less robotic offline voice.
echo "[4/4] Preparing Tony's natural local voice (best-effort)..."
if [ ! -x "$PIPER_VENV/bin/python" ]; then
  python3 -m venv "$PIPER_VENV" || true
fi
if [ -x "$PIPER_VENV/bin/python" ]; then
  "$PIPER_VENV/bin/python" -m pip install --disable-pip-version-check --quiet --upgrade pip >/dev/null 2>&1 || true
  "$PIPER_VENV/bin/python" -m pip install --disable-pip-version-check --quiet "piper-tts>=1.4" || true
  if [ ! -s "$PIPER_VOICES/en_US-lessac-medium.onnx" ]; then
    (cd "$PIPER_VOICES" && "$PIPER_VENV/bin/python" -m piper.download_voices en_US-lessac-medium --data-dir "$PIPER_VOICES") || true
  fi
fi


# Verify the Piper CLI instead of assuming a successful pip install means it runs.
if [ -x "$PIPER_VENV/bin/python" ] && [ -s "$PIPER_VOICES/en_US-lessac-medium.onnx" ]; then
  "$PIPER_VENV/bin/python" -m piper --help >/dev/null 2>&1 || {
    echo "WARNING: Piper installed but its CLI is not healthy; Nexora will use eSpeak until repaired."
  }
fi

if [ -x "$WHISPER_DIR/build/bin/whisper-cli" ] && [ -s "$MODEL" ]; then
  echo "✓ Local speech recognition ready."
else
  echo "⚠ Whisper setup is incomplete. Voice input will stay disabled until this script succeeds."
fi
if [ -x "$PIPER_VENV/bin/python" ] && [ -s "$PIPER_VOICES/en_US-lessac-medium.onnx" ]; then
  echo "✓ Natural Tony voice ready."
elif command -v espeak-ng >/dev/null 2>&1; then
  echo "✓ Lightweight Tony speech fallback ready (eSpeak NG)."
else
  echo "⚠ No TTS backend detected."
fi

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user restart nexora-voice.service 2>/dev/null || true

#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
ok(){ printf '  [OK]   %s\n' "$1"; }
bad(){ printf '  [FAIL] %s\n' "$1"; fail=1; }
info(){ printf '  [INFO] %s\n' "$1"; }

printf '\nNexora OS V1 Public Beta doctor\n\n'
if "$ROOT/scripts/static-audit.sh" >/tmp/nexora-static-audit.log 2>&1; then ok "source/static audit passed"; else bad "static audit failed (see /tmp/nexora-static-audit.log)"; fi

for cmd in kwin_wayland Xwayland dbus-run-session systemctl python3 sqlite3 curl wpctl pactl parec ffmpeg flatpak; do
  command -v "$cmd" >/dev/null 2>&1 && ok "$cmd found" || bad "$cmd missing"
done
[[ -x "$ROOT/build-out/nexora-shell" ]] && ok "build contains nexora-shell" || bad "nexora-shell was not built"
[[ -x "$ROOT/build-out/nexora-core" ]] && ok "build contains nexora-core" || bad "nexora-core was not built"
[[ -x "$HOME/.local/bin/nexora-shell" ]] && ok "Nexora shell installed" || bad "Nexora shell not installed"
[[ -x "$HOME/.local/bin/nexora-core" ]] && ok "Nexora Core installed" || bad "Nexora Core not installed"

RELEASE="$HOME/.local/share/nexora/release"
if [[ -f "$RELEASE" ]] && grep -q '^VERSION=1.0.1-beta.1$' "$RELEASE"; then ok "release marker is V1 Public Beta"; else bad "release marker missing/wrong"; fi

for svc in nexora-core.service nexora-context.service nexora-tony.service nexora-voice.service; do
  systemctl --user is-enabled "$svc" >/dev/null 2>&1 && ok "$svc enabled" || bad "$svc not enabled"
  systemctl --user is-active "$svc" >/dev/null 2>&1 && ok "$svc active" || info "$svc will start with Nexora session"
done

if command -v busctl >/dev/null 2>&1 && busctl --user call org.nexora.Core /Core org.nexora.Core Ping >/tmp/nexora-core-ping 2>/dev/null; then
  grep -q 'nexora-core/1.0.1-beta.1' /tmp/nexora-core-ping && ok "Nexora Core V1 API responding" || bad "Core API returned unexpected version"
else info "Core API not responding in recovery session"; fi

curl -fsS --max-time 1 http://127.0.0.1:8766/health >/tmp/nexora-tony-health 2>/dev/null && grep -q '1.0.1-beta.1' /tmp/nexora-tony-health && ok "Tony V1 API responding" || bad "Tony API unavailable/version mismatch"
curl -fsS --max-time 2 http://127.0.0.1:8767/health >/tmp/nexora-voice-health 2>/dev/null && grep -q '1.0.1-beta.1' /tmp/nexora-voice-health && ok "Voice V1 API responding" || bad "Voice API unavailable/version mismatch"

VOICE_ROOT="$HOME/.local/share/nexora/voice"
[[ -x "$VOICE_ROOT/whisper.cpp/build/bin/whisper-cli" && -s "$VOICE_ROOT/models/ggml-base.en.bin" ]] && ok "Whisper STT ready" || bad "Whisper STT incomplete"
[[ -x "$HOME/.local/share/nexora/llama.cpp/build/bin/llama-server" ]] && ok "llama.cpp runtime ready" || bad "llama.cpp runtime missing"
[[ -s "$HOME/.local/share/nexora/models/Qwen3-0.6B-Q4_0.gguf" ]] && ok "Tony fast model cached" || bad "Tony fast model missing"

if systemctl --user is-active pipewire.service >/dev/null 2>&1 || systemctl --user is-active pipewire.socket >/dev/null 2>&1; then ok "PipeWire active"; else info "PipeWire will start with Nexora"; fi
info "Public ISO builder: ./iso/build-iso.sh"
info "Voice test: ./scripts/voice-test.sh"
info "Service/RAM view: ./scripts/service-status.sh"
printf '\n'
if (( fail )); then echo "Doctor found a blocking problem. Do NOT log out yet."; exit 1; else echo "READY: Nexora OS V1 Public Beta is safe to test."; fi

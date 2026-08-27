#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf '\n=== Nexora OS V1 Public Beta upgrade ===\n'
printf 'Focus: OS UX, reliable Voice, real PTY console, public-beta/ISO readiness.\n\n'

"$ROOT/scripts/bootstrap.sh"
"$ROOT/scripts/migrate-v0.7.sh"
rm -rf "$ROOT/build-out"
"$ROOT/scripts/build.sh"
# Important: install services before the session. This also guarantees the
# canonical Voice daemon path is updated from older 0.8.x builds.
"$ROOT/scripts/install-user-service.sh"
"$ROOT/scripts/install-session.sh"
"$ROOT/scripts/install-identity.sh"

if [[ ! -x "$HOME/.local/share/nexora/voice/whisper.cpp/build/bin/whisper-cli" ]]; then
  echo 'Voice runtime is missing; preparing it now...'
  "$ROOT/scripts/setup-voice.sh" || true
fi
if [[ ! -s "$HOME/.local/share/nexora/models/Qwen3-0.6B-Q4_0.gguf" ]]; then
  echo 'Tony fast model is missing; preparing it now...'
  "$ROOT/scripts/setup-tony.sh" fast
fi

systemctl --user daemon-reload
systemctl --user reset-failed nexora-core.service nexora-context.service nexora-tony.service nexora-voice.service nexora-llm.service || true
systemctl --user restart nexora-core.service nexora-context.service nexora-tony.service nexora-voice.service || true

"$ROOT/scripts/doctor.sh"
printf '\nNexora OS V1 Public Beta installed. Log out and choose Nexora OS.\n'
printf 'After testing V1, build the public ISO with: ./iso/build-iso.sh\n'

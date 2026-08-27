# Nexora Voice V1

## Ports

- Tony: `127.0.0.1:8766`
- Voice: `127.0.0.1:8767`
- llama.cpp: `127.0.0.1:8081` when loaded

All bind to loopback.

## Voice API

`GET /health` — voice state and local backend status.

`POST /listen/start` — begins local microphone capture.

`POST /listen/stop` — stops capture and performs local Whisper transcription. Returns `transcript`.

`POST /speak {"text":"..."}` — begins local TTS playback.

`POST /speak/stop` — stop current speech.

`POST /config` — supports `speak_replies`, `tts_backend`, `max_record_seconds`.

## Privacy

Nexora V1 does not run an always-hot microphone. Recording only starts after an explicit UI/keyboard action. A 20-second default recording safety limit prevents accidental indefinite capture.

## Backends

Speech recognition: `whisper.cpp` + `ggml-base.en.bin`.

Speech synthesis: Piper `en_US-lessac-medium` when installed, otherwise `espeak-ng`.

Recording/playback: PipeWire first, ALSA fallback.

## VMware development note

A VM can expose speaker output while still hiding the host microphone. If the Voice API is online but recording fails, first verify that the VM has an audio device/input attached and that Debian can see a PipeWire/ALSA capture source. Run `./scripts/voice-test.sh` before changing Nexora services.

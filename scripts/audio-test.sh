#!/usr/bin/env bash
set -u
printf '\nNexora OS 1.0.1-beta.1 audio diagnostic\n\n'
printf '%s\n' '--- PipeWire/WirePlumber ---'
systemctl --user --no-pager --full status pipewire.service wireplumber.service 2>/dev/null | tail -n 35 || true
printf '\n%s\n' '--- wpctl ---'
wpctl status 2>/dev/null | sed -n '1,100p' || true
wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true
printf '\n%s\n' '--- pactl ---'
pactl info 2>/dev/null | grep -E 'Server Name|Default Sink' || true
pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null || true
pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null || true
printf '\n%s\n' '--- Core API ---'
if command -v busctl >/dev/null 2>&1; then
  busctl --user call org.nexora.Core /Core org.nexora.Core Ping 2>/dev/null || true
fi

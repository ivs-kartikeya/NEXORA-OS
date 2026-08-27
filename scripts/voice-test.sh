#!/usr/bin/env bash
set -u
BASE="http://127.0.0.1:8767"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "===== Nexora Voice 1.0.1-beta.1 ====="
systemctl --user --no-pager --full status nexora-voice.service 2>/dev/null | sed -n '1,16p' || true
echo
echo "Health:"
curl -s --max-time 2 "$BASE/health" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "Voice service unavailable"

echo
echo "Speaker test (you should hear Tony now):"
resp=$(curl -s --max-time 40 -X POST -H 'Content-Type: application/json' \
  -d '{"text":"Tony voice output is working through Nexora audio."}' "$BASE/speak" 2>/dev/null || true)
echo "$resp" | python3 -m json.tool 2>/dev/null || echo "$resp"
sleep 1

echo
echo "Microphone test:"
echo "Press ENTER, speak a short sentence for about 3 seconds, then press ENTER again."
read -r _
curl -s --max-time 4 -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/listen/start" | python3 -m json.tool 2>/dev/null || true
read -r _
curl -s --max-time 65 -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/listen/stop" | python3 -m json.tool 2>/dev/null || true

echo
echo "If either test failed, inspect:"
echo "  journalctl --user -u nexora-voice.service -n 80 --no-pager"
echo "Repair voice stack:"
echo "  $ROOT/scripts/setup-voice.sh"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "${1:-status}" in
  load)
    systemctl --user reset-failed nexora-llm.service || true
    systemctl --user start nexora-llm.service
    ;;
  unload) systemctl --user stop nexora-llm.service ;;
  restart)
    systemctl --user reset-failed nexora-llm.service || true
    systemctl --user restart nexora-llm.service
    ;;
  fast)
    "$ROOT/scripts/setup-tony.sh" fast
    ;;
  quality)
    "$ROOT/scripts/setup-tony.sh" quality
    ;;
  repair)
    systemctl --user stop nexora-llm.service || true
    systemctl --user reset-failed nexora-llm.service || true
    "$ROOT/scripts/setup-tony.sh" fast
    ;;
  test)
    systemctl --user start nexora-llm.service
    echo "Waiting for local model..."
    for _ in $(seq 1 120); do
      if curl -fsS --max-time 1 http://127.0.0.1:8081/health >/dev/null 2>&1; then
        echo "✓ Tony model is responding."
        curl -fsS --max-time 2 http://127.0.0.1:8081/health || true
        echo
        exit 0
      fi
      sleep 0.25
    done
    echo "✗ Tony model did not become ready within 30 seconds."
    journalctl --user -u nexora-llm.service -n 40 --no-pager || true
    exit 1
    ;;
  status)
    echo "--- Tony service ---"
    systemctl --user --no-pager status nexora-tony.service || true
    echo "--- Model service ---"
    systemctl --user --no-pager status nexora-llm.service || true
    echo "--- Local model health ---"
    curl -fsS --max-time 1 http://127.0.0.1:8081/health 2>/dev/null || echo "model sleeping/offline"
    echo
    if [[ -f "$HOME/.config/nexora/tony.env" ]]; then
      grep -E '^TONY_(MODEL_FILE|MODEL_PROFILE|CONTEXT|THREADS|MAX_TOKENS)=' "$HOME/.config/nexora/tony.env" || true
    fi
    ;;
  *) echo "Usage: $0 [load|unload|restart|fast|quality|repair|test|status]"; exit 2 ;;
esac

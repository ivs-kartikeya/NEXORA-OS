#!/usr/bin/env bash
set -u
printf '\nNexora OS 1.0.1-beta.1 service health\n\n'
for svc in nexora-core.service nexora-context.service nexora-tony.service nexora-voice.service nexora-llm.service; do
  active="$(systemctl --user is-active "$svc" 2>/dev/null || true)"
  enabled="$(systemctl --user is-enabled "$svc" 2>/dev/null || true)"
  mem="$(systemctl --user show "$svc" -p MemoryCurrent --value 2>/dev/null || true)"
  if [[ "$mem" =~ ^[0-9]+$ ]]; then mem_mib="$((mem/1024/1024)) MiB"; else mem_mib="-"; fi
  printf '%-24s active=%-10s enabled=%-10s ram=%s\n' "$svc" "${active:-unknown}" "${enabled:-unknown}" "$mem_mib"
done
printf '\nCore D-Bus: '
if command -v busctl >/dev/null 2>&1 && busctl --user call org.nexora.Core /Core org.nexora.Core Ping >/tmp/nexora-core-ping 2>/dev/null; then
  cat /tmp/nexora-core-ping
else
  echo 'not responding'
fi
printf 'Tony API: '
if curl -fsS --max-time 1 http://127.0.0.1:8766/health 2>/dev/null; then echo; else echo 'offline'; fi

printf 'Voice API: '
if curl -fsS --max-time 1 http://127.0.0.1:8767/health 2>/dev/null; then echo; else echo 'offline'; fi

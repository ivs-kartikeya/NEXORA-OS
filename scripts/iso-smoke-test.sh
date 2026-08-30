#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
ISO="${1:-$ROOT/dist/NexoraOS-$VERSION-amd64.iso}"
TIMEOUT_SECONDS="${NEXORA_SMOKE_TIMEOUT:-480}"
RAM_MB="${NEXORA_SMOKE_RAM_MB:-3072}"
CPUS="${NEXORA_SMOKE_CPUS:-2}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 2; }; }
for cmd in bsdtar qemu-system-x86_64 grep awk; do need "$cmd"; done

[[ -s "$ISO" ]] || { echo "ISO not found or empty: $ISO" >&2; exit 2; }

tmp="$(mktemp -d)"
serial="$tmp/serial.log"
qemu_pid=""
cleanup() {
  if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
    kill -TERM "$qemu_pid" 2>/dev/null || true
    sleep 1
    kill -KILL "$qemu_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

mapfile -t iso_paths < <(bsdtar -tf "$ISO" | sed 's#^\./##')

extract_first_large() {
  local regex="$1" output="$2" min_bytes="$3" path candidate size
  for path in "${iso_paths[@]}"; do
    [[ "$path" =~ $regex ]] || continue
    candidate="$tmp/candidate"
    rm -f "$candidate"
    if bsdtar -xOf "$ISO" "$path" >"$candidate" 2>/dev/null; then
      size="$(stat -c '%s' "$candidate" 2>/dev/null || echo 0)"
      if (( size >= min_bytes )); then
        mv "$candidate" "$output"
        printf '%s\n' "$path"
        return 0
      fi
    fi
  done
  return 1
}

kernel_path="$(extract_first_large '^live/vmlinuz([^/]*)$' "$tmp/vmlinuz" 1000000)" || {
  echo "Could not extract a Linux kernel from $ISO" >&2
  exit 3
}
initrd_path="$(extract_first_large '^live/initrd([^/]*)$' "$tmp/initrd.img" 1000000)" || {
  echo "Could not extract an initrd from $ISO" >&2
  exit 3
}

echo "Nexora ISO smoke test"
echo "  ISO:     $ISO"
echo "  Kernel:  $kernel_path"
echo "  Initrd:  $initrd_path"
echo "  Timeout: ${TIMEOUT_SECONDS}s"

# The extra dialout membership exists only in this disposable smoke-test boot,
# allowing the unprivileged Nexora session supervisor to write its readiness
# marker to the emulated serial port. Normal live boots keep Debian's defaults.
LIVE_GROUPS="audio,cdrom,dip,floppy,video,plugdev,netdev,powerdev,scanner,bluetooth,dialout"
KERNEL_ARGS="boot=live components live-config.nox11autologin live-config.username=nexora live-config.hostname=nexora live-config.user-default-groups=$LIVE_GROUPS locales=en_US.UTF-8 keyboard-layouts=us console=tty0 console=ttyS0,115200n8 nexora.ci-smoke=1"

: >"$serial"
qemu-system-x86_64 \
  -machine q35,accel=tcg \
  -m "$RAM_MB" \
  -smp "$CPUS" \
  -display none \
  -serial "file:$serial" \
  -no-reboot \
  -no-shutdown \
  -device virtio-vga \
  -cdrom "$ISO" \
  -kernel "$tmp/vmlinuz" \
  -initrd "$tmp/initrd.img" \
  -append "$KERNEL_ARGS" \
  >/dev/null 2>&1 &
qemu_pid=$!

echo "  QEMU pid: $qemu_pid"

for (( elapsed=0; elapsed<TIMEOUT_SECONDS; elapsed++ )); do
  if grep -Fq 'NEXORA_SMOKE:SESSION_READY' "$serial"; then
    echo "NEXORA ISO SMOKE PASSED: live user reached a stable Nexora desktop session."
    kill -TERM "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
    qemu_pid=""
    exit 0
  fi

  if grep -Eq 'NEXORA_SMOKE:(PREFLIGHT_FAIL|SESSION_CRASH|SESSION_EXITED_EARLY)' "$serial"; then
    echo "NEXORA ISO SMOKE FAILED: Nexora session reported a startup failure." >&2
    tail -n 160 "$serial" >&2 || true
    exit 4
  fi

  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    wait "$qemu_pid" || qemu_rc=$?
    qemu_rc="${qemu_rc:-0}"
    echo "NEXORA ISO SMOKE FAILED: QEMU exited before session readiness (rc=$qemu_rc)." >&2
    tail -n 160 "$serial" >&2 || true
    qemu_pid=""
    exit 5
  fi

  if (( elapsed > 0 && elapsed % 60 == 0 )); then
    echo "  waiting for Nexora session... ${elapsed}s"
  fi
  sleep 1
done

echo "NEXORA ISO SMOKE FAILED: timeout after ${TIMEOUT_SECONDS}s." >&2
tail -n 200 "$serial" >&2 || true
exit 6

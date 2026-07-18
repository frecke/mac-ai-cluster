#!/usr/bin/env bash
# Session-scoped GPU wired-memory limit. Reverts on reboot by design.
# usage: gpu-wired.sh <head|worker|reset> [--print-only]
set -euo pipefail
ROLE="${1:-head}"

MEM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
[ "$MEM_BYTES" -gt 0 ] || { echo "not macOS / cannot read hw.memsize" >&2; exit 1; }
RAM_GB=$(( MEM_BYTES / 1024 / 1024 / 1024 ))

if [ "$ROLE" = "reset" ]; then
  MB=0
elif [ "$ROLE" = "worker" ]; then
  MB=$(( (RAM_GB - 6)  * 1024 ))   # inference only, run lean
else
  MB=$(( (RAM_GB - 12) * 1024 ))   # editor + agent + browser headroom
fi

[ "${2:-}" = "--print-only" ] && { echo "$MB"; exit 0; }

sysctl -w iogpu.wired_limit_mb="$MB" >/dev/null
if [ "$MB" -eq 0 ]; then
  echo "  ✓ wired limit reset to macOS default (~$(( RAM_GB * 3 / 4 ))GB)"
else
  echo "  ✓ wired limit ${MB}MB (${ROLE}, ${RAM_GB}GB) — this boot only"
fi

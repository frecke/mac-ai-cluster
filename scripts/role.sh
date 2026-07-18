#!/usr/bin/env bash
# Auto-detect node role from chip; override with NODE_ROLE (set it for this
# machine in mise.local.toml — see mise.local.toml.example).
set -euo pipefail
if [ -n "${NODE_ROLE:-}" ]; then echo "$NODE_ROLE"; exit 0; fi
CHIP="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
case "$CHIP" in
  *M5*) echo head ;;
  *M4*) echo worker ;;
  *)
    echo "role.sh: unrecognized chip '$CHIP' — guessing 'head'." >&2
    echo "  Set NODE_ROLE explicitly in mise.local.toml instead of relying on this guess:" >&2
    echo "  cp mise.local.toml.example mise.local.toml   # then edit NODE_ROLE" >&2
    echo head
    ;;
esac

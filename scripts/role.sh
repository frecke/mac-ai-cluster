#!/usr/bin/env bash
# Auto-detect node role from chip; override with NODE_ROLE.
set -euo pipefail
if [ -n "${NODE_ROLE:-}" ]; then echo "$NODE_ROLE"; exit 0; fi
case "$(sysctl -n machdep.cpu.brand_string 2>/dev/null)" in
  *M5*) echo head ;;
  *M4*) echo worker ;;
  *)    echo head ;;
esac

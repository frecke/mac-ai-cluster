#!/usr/bin/env bash
# just stop-ai-cluster — unload models, quit EXO, hand memory back to the OS.
cd "$(dirname "$0")/.."; source scripts/lib.sh
ROLE="$(bash scripts/role.sh)"

hdr "Stopping AI cluster  ${DIM}(role=$ROLE)${RST}"

# 1. unload instances first so EXO frees GPU buffers cleanly
if exo_up; then
  bash scripts/unload-all.sh
  sleep 2
else
  note "EXO not running"
fi

# 2. quit the app (graceful, then firm)
if pgrep -qx EXO 2>/dev/null || pgrep -qf 'EXO.app' 2>/dev/null; then
  osascript -e 'tell application "EXO" to quit' 2>/dev/null || true
  sleep 3
  pkill -f 'EXO.app' 2>/dev/null || true
  ok "EXO stopped"
fi

# 3. stray source-run workers
pkill -f 'uv run exo' 2>/dev/null && ok "stopped source-run exo" || true

# 4. hand the memory back
sudo bash scripts/gpu-wired.sh reset

# 5. let the worker sleep again
if [ "$ROLE" = "worker" ]; then
  sudo pmset -a disablesleep 0 && ok "sleep re-enabled"
fi

# 6. report what came back
FREE=$(vm_stat | awk '/Pages free/{gsub(/\./,"",$3); print $3}')
PGSZ=$(pagesize 2>/dev/null || echo 16384)
printf "\n  ${GRN}✓${RST} free memory: %d GB of %d GB\n" \
  $(( FREE * PGSZ / 1024 / 1024 / 1024 )) "$(ram_gb)"
note "wired limit is back to the macOS default until you run start-ai-cluster again"

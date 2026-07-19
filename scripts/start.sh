#!/usr/bin/env bash
# just start-ai-cluster [profile]
cd "$(dirname "$0")/.."; source scripts/lib.sh
PROFILE="${1:-throughput}"
ROLE="$(bash scripts/role.sh)"

hdr "Starting AI cluster  ${DIM}(role=$ROLE, profile=$PROFILE)${RST}"

# 1. session-scoped memory limit
sudo bash scripts/gpu-wired.sh "$ROLE"

# 2. worker power posture: no sleep + caffeinate + high power mode
if [ "$ROLE" = "worker" ]; then
  bash scripts/power.sh on
fi

# 3. bring EXO up
if ! exo_up; then
  open -a EXO 2>/dev/null || { bad "EXO.app not installed (just exo-install)"; exit 1; }
  printf "  waiting for API"
  for _ in $(seq 1 40); do exo_up && break; printf "."; sleep 1; done
  echo
fi
exo_up || { bad "EXO API never came up at $EXO_API"; exit 1; }
ok "EXO API up"

# 4. wait for the peer before loading anything pooled
NODES=$(curl -s "$EXO_API/state" | jq '.topology.nodes // [] | length')
if [ "$NODES" -lt 2 ]; then
  printf "  waiting for peer node"
  for _ in $(seq 1 30); do
    NODES=$(curl -s "$EXO_API/state" | jq '.topology.nodes // [] | length')
    [ "$NODES" -ge 2 ] && break; printf "."; sleep 1
  done
  echo
fi
if [ "$NODES" -ge 2 ]; then
  ok "$NODES nodes clustered"
else
  warn "only $NODES node — 'advisor' profile needs 2 (run start on the other Mac)"
fi

# 5. load the tier
[ "$PROFILE" = "none" ] || bash scripts/profile.sh "$PROFILE"

hdr "Ready"
note "just cluster-status   ·   just stop-ai-cluster when you're done"

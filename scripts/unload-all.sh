#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
IDS=$(curl -s "$EXO_API/state" | jq -r '.instances[]?.id // empty')
[ -z "$IDS" ] && { note "nothing loaded"; exit 0; }
for id in $IDS; do curl -sX DELETE "$EXO_API/instance/$id" >/dev/null; done
ok "unloaded all instances"

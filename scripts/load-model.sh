#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
M="$1"
# Rank: tensor+jaccl best, then tensor, then anything valid.
INST=$(curl -s "$EXO_API/instance/previews?model_id=$M" | jq -c '
  [.previews[] | select(.error == null)]
  | sort_by( (if .sharding=="Tensor" then 0 else 1 end),
             (if (.instance_meta|tostring|test("jaccl";"i")) then 0 else 1 end) )
  | .[0]')
if [ -z "$INST" ] || [ "$INST" = "null" ]; then bad "no valid placement for $M"; exit 1; fi
echo "  → $(echo "$INST" | jq -r '"\(.sharding) / \(.instance_meta)"')"
curl -sX POST "$EXO_API/instance" -H 'Content-Type: application/json' \
  -d "{\"instance\": $(echo "$INST" | jq -c .instance)}" | jq -r '.message'
ok "$M queued"

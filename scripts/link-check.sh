#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
system_profiler SPThunderboltDataType | grep -iE "speed|link status" || true
echo
curl -s "$EXO_API/instance/previews?model_id=mlx-community/Llama-3.2-1B-Instruct-4bit" \
  | jq '[.previews[]? | select(.error==null) | {sharding, instance_meta}] | unique'
note "jaccl = RDMA · MlxRing = TCP fallback"

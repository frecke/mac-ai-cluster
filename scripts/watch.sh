#!/usr/bin/env bash
# Live cluster view — nodes, instances, runner states, downloads.
# usage: watch.sh [interval-seconds]   (Ctrl-C to quit)
cd "$(dirname "$0")/.."; source scripts/lib.sh
IV="${1:-3}"

draw() {
  local st out
  if ! st="$(curl -sf --max-time 2 "$EXO_API/state" 2>/dev/null)"; then
    printf '\033c'
    bad "EXO API unreachable at $EXO_API"
    return
  fi
  out="$(printf '%s' "$st" | jq -r '
    . as $s
    | "NODES",
      (if ($s.topology.nodes | length) == 0 then "  (none clustered)" else
        ($s.topology.nodes[] | $s.nodeIdentities[.] as $id | $s.nodeMemory[.] as $m
          | "  \($id.friendlyName)  ·  \($id.chipId)  ·  " +
            "\(((($m.ramTotal.inBytes - $m.ramAvailable.inBytes) / 1073741824) * 10 | floor) / 10)/" +
            "\(($m.ramTotal.inBytes / 1073741824) | floor)GB used")
      end),
      "",
      "INSTANCES",
      (if ($s.instances | length) == 0 then "  (none loaded)" else
        ($s.instances | to_entries[] | .key[:8] as $iid | .value[]
          | "  \($iid)  \(.shardAssignments.modelId)",
            (.shardAssignments.runnerToShard | keys[]
              | "    runner \(.[:8])  \($s.runners[.] | keys[0] // "unknown")"))
      end),
      "",
      "DOWNLOADS (active)",
      ([$s.downloads // {} | .[]? | .[]? | to_entries[0] | .key as $k | .value
        | select(.total.inBytes? and .downloaded.inBytes?)
        # zero-byte DownloadPending entries are catalog placeholders, not activity
        | select(.downloaded.inBytes > 0 or $k != "DownloadPending")
        | select(.downloaded.inBytes < .total.inBytes)
        | "  \(.shardMetadata[]?.modelCard.modelId // "?")  " +
          "\((.downloaded.inBytes / .total.inBytes * 100) | floor)%  " +
          "(\((.downloaded.inBytes / 1073741824 * 10 | floor) / 10)/" +
          "\((.total.inBytes / 1073741824 * 10 | floor) / 10)GB)"]
       | if length == 0 then "  (none)" else unique[] end)
  ')"
  printf '\033caicluster watch — %s  (every %ss, Ctrl-C to quit)\n\n%s\n' \
    "$(date +%H:%M:%S)" "$IV" "$out"
}

if [ -n "${AIC_WATCH_ONCE:-}" ]; then draw; exit 0; fi
while :; do draw; sleep "$IV"; done

#!/usr/bin/env bash
# Measure TTFT + decode throughput against a loaded model, via the same
# OpenAI-compatible endpoint opencode/codex use. Appends bench/perf.jsonl
# so you can compare placements (1-node vs pooled, Ring vs RDMA) over time.
# usage: perf.sh [model] [max-tokens]     model defaults to whatever is loaded
cd "$(dirname "$0")/.."; source scripts/lib.sh
M="${1:-}"
if [ -z "$M" ]; then
  M="$(curl -s "$EXO_API/state" | jq -r '[.instances[]?[]?.shardAssignments.modelId] | first // empty')"
  [ -n "$M" ] || { bad "no model loaded and none given (just load <model>)"; exit 1; }
fi
TG="${2:-128}"
have python3 || { bad "python3 missing (mise install)"; exit 1; }
mkdir -p bench

EXO_API="$EXO_API" MODEL="$M" TG="$TG" python3 - <<'PY'
import json, os, time, urllib.request

api, model, tg = os.environ["EXO_API"], os.environ["MODEL"], int(os.environ["TG"])
body = json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": "Write a limerick about GPUs, then explain it line by line."}],
    "max_tokens": tg,
    "stream": True,
}).encode()
req = urllib.request.Request(api + "/v1/chat/completions", data=body,
                             headers={"Content-Type": "application/json"})
t0 = time.time(); t_first = None; n = 0
with urllib.request.urlopen(req, timeout=180) as r:
    for line in r:
        line = line.strip()
        if not line.startswith(b"data:"):
            continue
        payload = line[5:].strip()
        if payload == b"[DONE]":
            break
        try:
            d = json.loads(payload)
        except ValueError:
            continue
        if d.get("choices", [{}])[0].get("delta", {}).get("content"):
            n += 1
            if t_first is None:
                t_first = time.time()
t1 = time.time()
ttft = (t_first or t1) - t0
gen = t1 - (t_first or t1)
tps = (n - 1) / gen if gen > 0 and n > 1 else 0.0
rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "model": model,
       "ttft_s": round(ttft, 2), "tokens": n, "tok_per_s": round(tps, 1)}
print(f"  model:   {model}")
print(f"  ttft:    {rec['ttft_s']}s")
print(f"  tokens:  {n}")
print(f"  decode:  {rec['tok_per_s']} tok/s")
with open("bench/perf.jsonl", "a") as f:
    f.write(json.dumps(rec) + "\n")
PY
ok "appended to bench/perf.jsonl"

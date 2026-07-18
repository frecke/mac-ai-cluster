# Two-Mac Local Inference Cluster — Setup Guide

**#1** MBP 14" 2026 M5 Pro 48GB — head node, coding agent, git repo · `192.168.99.5`
**#2** MBP 14" 2024 M4 Pro 48GB — inference worker · `192.168.99.4`
Both on macOS 26.2+, both have WiFi internet, TB link between them.

---

## TL;DR of the architecture decision

**Drop Ollama as the cluster layer.** Ollama has no distributed inference — it never shipped it ([issue #5983](https://github.com/ollama/ollama/issues/5983) is still open). Everything calling itself an "Ollama cluster" is a load balancer in front of N independent Ollama instances. That gives you throughput, not pooled memory.

**Use EXO.** It's the only thing that does what you want on this exact hardware: MLX backend, tensor + pipeline parallel, automatic topology-aware placement, and day-0 RDMA over Thunderbolt 5 on macOS 26.2. It serves OpenAI Chat Completions, OpenAI Responses, **Claude Messages**, and Ollama-compatible APIs from one port — so all four agent CLIs can point at it without a translation proxy.

**llama.cpp RPC is the fallback**, not the primary. It works and it's simpler to reason about, but it's pipeline-only, layer-split, and adds a full network round trip per decode step. On RDMA-capable hardware you're leaving a lot on the table.

---

## Phase 0 — The decision that costs you something

RDMA over Thunderbolt is a step-change: inter-device latency drops from ~300µs to single-digit µs, ~80 Gb/s on TB5. It's the difference between "distributed inference is a tax" and "distributed inference is a speedup."

**But enabling it will destroy your current network setup.** EXO's `tmp/set_rdma_network_config.sh` disables Thunderbolt Bridge and puts every RDMA port on DHCP. Your `192.168.99.0/24` static addressing and MTU 9000 jumbo frames go away — and they become irrelevant, because RDMA bypasses the IP stack entirely.

Two hard requirements before you commit:

1. **A real TB5 cable.** You wrote TB4. A TB4 cable will not negotiate RDMA. Check: `system_profiler SPThunderboltDataType | grep -i "speed\|link"` — you want to see 80 Gb/s.
2. **Byte-identical OS builds.** Not "both on 26.2" — the exact same build string, including betas. Mismatched builds fail RDMA port discovery in a way that looks like a hardware problem.

```bash
# run on BOTH, output must match character for character
sw_vers -productVersion && sw_vers -buildVersion
```

If either check fails, skip to [Appendix A](#appendix-a--fallback-llamacpp-rpc-over-your-existing-tb-link) and use llama.cpp RPC over the network you already have.

> Keep WiFi up on both machines. EXO downloads models from HuggingFace, and libp2p peer discovery uses your regular network. RDMA carries the tensor traffic only.

---

## Phase 1 — Prep both machines

Run on **both** #1 and #2.

```bash
# Xcode is required — provides the Metal toolchain MLX compiles against.
# Xcode Command Line Tools alone are NOT enough.
xcode-select -p   # should point into Xcode.app, not /Library/Developer/CommandLineTools
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept

brew install uv node
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup toolchain install nightly
```

### macmon — M5-specific gotcha

EXO uses `macmon` for hardware telemetry. **Homebrew's macmon 0.6.1 crashes on M5**, which is your #1. Install the pinned fork on both machines so versions match:

```bash
cargo install --git https://github.com/vladkens/macmon \
  --rev a1cd06b6cc0d5e61db24fd8832e74cd992097a7d \
  macmon --force
```

### Raise the GPU wired-memory limit

macOS caps GPU-accessible memory around 75% of RAM (~36GB of your 48GB). You need more than that to make pooling worthwhile.

```bash
# #2 (dedicated inference — be aggressive)
sudo sysctl iogpu.wired_limit_mb=43008   # 42GB

# #1 (also running IDE, agent, browser — leave headroom)
sudo sysctl iogpu.wired_limit_mb=36864   # 36GB
```

Not persistent across reboot. Make it stick with a LaunchDaemon:

```bash
sudo tee /Library/LaunchDaemons/local.gpuwired.plist >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.gpuwired</string>
  <key>ProgramArguments</key>
  <array><string>/usr/sbin/sysctl</string><string>iogpu.wired_limit_mb=43008</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
sudo launchctl load /Library/LaunchDaemons/local.gpuwired.plist
```

Adjust the value per machine. Don't set it to the full 48GB — the OS needs memory too, and hitting the ceiling causes swap thrash that will make inference *slower* than not pooling at all.

---

## Phase 2 — Enable RDMA

Per machine, one time each. This requires physical access — it's a Recovery Mode operation.

1. Shut down.
2. Hold the power button ~10s until the boot options screen appears.
3. **Options** → Continue → **Utilities → Terminal**.
4. Run: `rdma_ctl enable`
5. Reboot.

Repeat on the other Mac. Then, from the exo repo (after Phase 3's clone):

```bash
sudo ./tmp/set_rdma_network_config.sh
```

This is the step that disables Thunderbolt Bridge and sets DHCP on the RDMA ports. Expect your `192.168.99.x` config to disappear.

**Caveats worth internalizing:**

- Every device must be physically cabled to every other device. With two Macs that's one cable — trivial now, but it means a third machine later needs a full mesh, not a chain.
- Two-node topology is the weakest case for tensor parallelism (~1.8x on 2 devices per EXO's own numbers, vs 3.2x on 4). You're getting the smaller half of the win.

---

## Phase 3 — Install EXO

You have two paths. **Start with the macOS app** — it's a background service with a menu bar UI, it handles the network profile installation, and it's much less to go wrong.

```
https://assets.exolabs.net/EXO-latest.dmg
```

Install on both machines. It'll ask permission to modify system settings and install a network profile. Requires macOS Tahoe 26.2+, which you have.

**Set a namespace on both** so you don't accidentally cluster with anything else on your network — menu bar → Advanced → namespace, or `EXO_LIBP2P_NAMESPACE=my-cluster`.

### Source install (do this if you want to pin versions or hack on it)

```bash
git clone https://github.com/exo-explore/exo && cd exo
cd dashboard && npm install && npm run build && cd ..
EXO_LIBP2P_NAMESPACE=my-cluster uv run exo
```

Dashboard + API at `http://localhost:52415`.

### Model storage

Models get large fast — gpt-oss-120b is ~63GB, and both nodes cache their own copies. If your internal SSD is tight, point EXO at an external:

```bash
EXO_MODELS_DIRS=/Volumes/Fast/exo-models uv run exo
```

You could also pre-download once and share read-only over your TB link via `EXO_MODELS_READ_ONLY_DIRS`, but honestly, just let both download over WiFi. Simpler.

---

## Phase 4 — Verify the cluster

Discovery is automatic. From #1:

```bash
curl -s http://localhost:52415/state | jq '.nodes'
```

You should see two nodes. If you only see one:

- Namespace mismatch between the machines
- OS build strings differ (check again — this is the usual culprit)
- Cable isn't TB5

Confirm RDMA is actually being used rather than falling back to TCP — check the dashboard topology view, or look for `jaccl` (Apple's RDMA collective communication library) in the placement metadata rather than `ring`:

```bash
curl -s "http://localhost:52415/instance/previews?model_id=llama-3.2-1b" \
  | jq '.previews[] | {sharding, instance_meta, error}'
```

`instance_meta: "MlxRing"` means TCP ring. `jaccl` means RDMA. If you're on ring when you expected jaccl, RDMA isn't up.

---

## Phase 5 — Model tiers

Your memory budget: ~42GB (#2) + ~36GB (#1) ≈ **78GB pooled, realistically usable**.

That number is the whole game. Here's how it partitions:

### Tier 1 — Fast workhorse (single machine, #2 only)

**`Qwen3-Coder-30B-A3B-Instruct` 4-bit MLX** — ~17GB. MoE with only ~3B active parameters, so it generates at 50-80 tok/s on an M4 Pro while reasoning like a much larger model. Trained specifically for agentic tool-calling loops. This is your daily driver: autocomplete, mechanical refactors, subagent fan-out, test generation.

Critically, it lives entirely on #2 — zero cross-machine traffic, and #1 stays cool and responsive for your editor.

### Tier 2 — Advisor (pooled across both)

**`gpt-oss-120b`** MXFP4 — ~63GB. Doesn't fit on either machine alone; fits comfortably pooled. Strong reasoning and tool use. This is your "I'm stuck on an architecture decision" / "review this diff for concurrency bugs" model.

Alternatives in the same slot: `GLM-4.5-Air` (~65GB at 4-bit), `Qwen3-Next-80B` variants.

### The coexistence math

63GB (Tier 2) + 17GB (Tier 1) = 80GB against ~78GB available. **Too tight.** You have two workable configurations:

| Config | Tier 1 | Tier 2 | When |
|---|---|---|---|
| **Throughput** | Qwen3-Coder-30B on #2 (17GB) + a 7-8B on #1 | — | Default. Fast, parallel, no interconnect cost. |
| **Advisor** | Qwen3-8B 4-bit (~5GB, on #2) | gpt-oss-120b pooled (63GB) | When you need the big model. Small model stays available for grunt work. |

Don't try to run all three at once. Flip between configs with the instance API.

### Loading a model

```bash
# 1. See valid placements (EXO computes these from live topology)
curl -s "http://localhost:52415/instance/previews?model_id=gpt-oss-120b" \
  | jq '.previews[] | select(.error == null) | {sharding, instance_meta, memory_delta_by_node}'

# 2. Create the instance from a placement you like
INST=$(curl -s "http://localhost:52415/instance/previews?model_id=gpt-oss-120b" \
  | jq -c '[.previews[] | select(.error == null)][0].instance')
curl -X POST http://localhost:52415/instance \
  -H 'Content-Type: application/json' -d "{\"instance\": $INST}"

# 3. Tear down when done
curl -X DELETE http://localhost:52415/instance/YOUR_INSTANCE_ID
```

Prefer previews with `"sharding": "Tensor"` and a `jaccl` instance_meta for the big model — that's the RDMA tensor-parallel path. Pipeline sharding on two nodes will serialize your decode steps.

---

## Phase 6 — Wire up the agents

All from #1, pointing at `localhost:52415` (EXO's local API proxies to the cluster).

### opencode — best local-model support of the four

`~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "exo": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "EXO Cluster",
      "options": { "baseURL": "http://localhost:52415/v1" },
      "models": {
        "gpt-oss-120b":                    { "name": "Advisor (pooled 120b)" },
        "Qwen3-Coder-30B-A3B-Instruct-4bit": { "name": "Workhorse (30b)" }
      }
    }
  }
}
```

Switch models mid-session with `/models`. This is the one to start with — model switching in-session maps exactly onto your two-tier setup.

### Claude Code — via the Claude Messages endpoint

EXO speaks `/v1/messages` natively, so no proxy needed:

```bash
export ANTHROPIC_BASE_URL=http://localhost:52415
export ANTHROPIC_AUTH_TOKEN=dummy
export ANTHROPIC_MODEL=gpt-oss-120b
claude
```

Expect rough edges. Claude Code leans hard on Anthropic-specific behaviors — prompt caching, tool-use formatting details, long system prompts. Local models tolerate this unevenly. Best used as: real Claude Code for primary work, this config for bulk/offline tasks where you don't want to burn tokens.

### Codex CLI

`~/.codex/config.toml`:

```toml
model = "gpt-oss-120b"
model_provider = "exo"

[model_providers.exo]
name = "EXO"
base_url = "http://localhost:52415/v1"
wire_api = "chat"
```

Codex works notably well with `gpt-oss` models specifically — same family lineage, similar harness expectations.

### GitHub Copilot CLI

Skip it. It's tied to GitHub's hosted models with no supported local endpoint override. Not worth fighting.

---

## Phase 7 — Measure before you believe

Don't trust the architecture, benchmark it. EXO ships the tool:

```bash
uv run bench/exo_bench.py \
  --model gpt-oss-120b \
  --pp 512,2048,8192 \
  --tg 256 \
  --max-nodes 2 \
  --repeat 3 \
  --json-out ~/exo-bench-120b.json
```

Compare `--sharding tensor` vs `pipeline`, and `--instance-meta jaccl` vs `ring`. The jaccl/tensor combination should win clearly; if it doesn't, RDMA isn't actually engaged.

**Test long prompts specifically.** `--pp 8192` matters more than `--pp 512` for your use case — coding agents send enormous contexts (file contents, diffs, tool results). Prefill throughput on long prompts is what you'll actually feel, and it's where distributed setups behave differently than the short-prompt benchmarks everyone publishes.

Also benchmark Tier 1 single-node on #2 for comparison. If pooled 120b prefill is dramatically worse than 30b single-node, the advisor tier is only worth invoking deliberately, not routing to automatically.

---

## Phase 8 — Ops convenience

Config-switching script — `~/bin/exo-config`:

```bash
#!/usr/bin/env bash
set -euo pipefail
EXO=http://localhost:52415

load() {
  local inst
  inst=$(curl -s "$EXO/instance/previews?model_id=$1" \
    | jq -c '[.previews[] | select(.error == null)] | sort_by(.instance_meta == "MlxRing") | .[0].instance')
  [ "$inst" = "null" ] && { echo "no valid placement for $1"; exit 1; }
  curl -sX POST "$EXO/instance" -H 'Content-Type: application/json' -d "{\"instance\": $inst}" | jq -r .message
}

clear_all() {
  curl -s "$EXO/state" | jq -r '.instances[]?.id // empty' \
    | xargs -I{} curl -sX DELETE "$EXO/instance/{}" >/dev/null
}

case "${1:-}" in
  throughput) clear_all; load Qwen3-Coder-30B-A3B-Instruct-4bit ;;
  advisor)    clear_all; load Qwen3-8B-4bit; load gpt-oss-120b ;;
  status)     curl -s "$EXO/state" | jq '{nodes: [.nodes[].id], instances: [.instances[]? | {id, model_id}]}' ;;
  clear)      clear_all ;;
  *) echo "usage: exo-config {throughput|advisor|status|clear}"; exit 1 ;;
esac
```

`chmod +x` it. Now `exo-config advisor` before a hard design session, `exo-config throughput` for normal work.

---

## Appendix A — Fallback: llama.cpp RPC over your existing TB link

If RDMA doesn't pan out (wrong cable, mismatched builds, or you'd rather keep your static `192.168.99.0/24` + jumbo frames), this works over plain IP.

On **both** machines, identical git revision — version mismatches hang at handshake or segfault mid-generation:

```bash
git clone https://github.com/ggml-org/llama.cpp && cd llama.cpp
git checkout <SAME_TAG_ON_BOTH>
cmake -B build -DGGML_RPC=ON -DGGML_METAL=ON
cmake --build build --config Release -j
```

On **#2** (worker):

```bash
./build/bin/rpc-server --host 192.168.99.4 -p 50052
```

On **#1** (head):

```bash
./build/bin/llama-server \
  -m ~/models/gpt-oss-120b-mxfp4.gguf \
  --rpc 192.168.99.4:50052 \
  -ngl 99 -c 32768 \
  --host 0.0.0.0 --port 8080
```

OpenAI-compatible endpoint at `http://localhost:8080/v1`. Same agent configs as Phase 6, different port.

**Understand what you're getting:** RPC is for capacity, not speed. It adds a network round trip to every decode step. If a model fits on one machine, running it split across two will be *slower*. Only reach for this when the model genuinely doesn't fit.

---

## Appendix B — Do you need a router?

Probably not. EXO already exposes OpenAI, Claude Messages, Responses, and Ollama APIs on a single port, and handles placement internally.

Add [llama-swap](https://github.com/mostlygeek/llama-swap) or [LiteLLM](https://github.com/BerriAI/litellm) in front only if you end up with genuinely separate backends — say EXO for pooled models plus a standalone llama.cpp on #2 for something MLX doesn't support. Then you'd want one endpoint that routes by model name. Until that's a real problem, another hop is just latency and another thing to debug.

---

## Things that will probably bite you

- **OS updates break the cluster.** Auto-update one Mac and not the other → RDMA silently stops discovering. Disable automatic macOS updates on both and update them together, deliberately.
- **Lid closed = node gone.** #2 sleeping drops it from the cluster mid-inference. `sudo pmset -a disablesleep 1` on #2, or keep it on AC with `caffeinate -s`.
- **Thermal throttling on a 14" chassis.** Neither of these is a Mac Studio. Sustained inference on a 14" MacBook Pro will throttle, and #2 doing continuous work will get loud and slow down. Watch it with `macmon`. This is the single biggest gap between your setup and the Mac Studio cluster benchmarks you'll see published.
- **First load of a 63GB model is slow.** Download over WiFi, twice (both nodes cache separately). Start it before you need it.
- **Tool-calling reliability is the real bottleneck**, not tokens/sec. Coding agents fail on malformed tool calls far more often than they fail on being slow. Qwen3-Coder and gpt-oss are both explicitly trained for this; a generic instruct model of the same size will frustrate you badly in an agent loop even if it benchmarks well.

---

## Sources

- [exo-explore/exo](https://github.com/exo-explore/exo) — README, RDMA setup, API, benchmarking
- [llama.cpp RPC backend README](https://github.com/ggml-org/llama.cpp/blob/master/tools/rpc/README.md)
- [Apple: Explore distributed inference and training with MLX — WWDC26](https://developer.apple.com/videos/play/wwdc2026/233/)
- [TN3205: Low-latency communication with RDMA over Thunderbolt](https://blog.massapi.com/posts/2026-03-18-1623-tn3205-low-latency-communication-with-rdma-over-thunderbolt/)
- [Jeff Geerling: 1.5 TB VRAM on Mac Studio — RDMA over Thunderbolt 5](https://www.jeffgeerling.com/blog/2025/15-tb-vram-on-mac-studio-rdma-over-thunderbolt-5/)
- [Ollama issue #5983: Run single large model on multiple machines](https://github.com/ollama/ollama/issues/5983)
- [AppleInsider: RDMA support on Thunderbolt 5](https://appleinsider.com/articles/25/12/20/ai-calculations-on-mac-cluster-gets-a-big-boost-from-new-rdma-support-on-thunderbolt-5)

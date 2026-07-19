set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load

export EXO_API := env_var_or_default("EXO_API", "http://localhost:52415")

# Role is auto-detected from the chip; override with NODE_ROLE=head|worker
role := `bash scripts/role.sh`

_default:
    @just --list --unsorted

# ---------------------------------------------------------------- setup

# Full first-run setup for THIS machine. Idempotent — safe to re-run.
bootstrap: _preflight deps macmon exo-install agents
    @echo ""
    @echo "✓ bootstrap complete on {{ role }} node"
    @echo "  next: just start-ai-cluster"

# Verify the machine is in a state worth building on
doctor:
    @bash scripts/doctor.sh

_preflight:
    @bash scripts/preflight.sh

# Xcode toolchain + mise-managed tools (node, uv, rust, jq)
deps:
    @bash scripts/deps.sh

# Pinned macmon fork — Homebrew's 0.6.1 segfaults on M5
macmon:
    @bash scripts/macmon.sh

# Show current vs target wired limit
gpu-status:
    @echo "current: $(sysctl -n iogpu.wired_limit_mb) MB  (0 = macOS default)"
    @echo "target:  $(bash scripts/gpu-wired.sh {{ role }} --print-only) MB  (role={{ role }})"

# Remove the old persistent LaunchDaemon, if you ever installed one
gpu-unpersist:
    @bash scripts/gpu-unpersist.sh

# Download + install the EXO macOS app
exo-install:
    @bash scripts/exo-install.sh

# ---------------------------------------------------------------- session

# Start a dev session: raise memory limit (this boot only), launch EXO, load a tier.
# profile: throughput (default) | advisor | none
start-ai-cluster profile="throughput":
    @bash scripts/start.sh "{{ profile }}"

# Stop everything and hand memory back to the OS.
stop-ai-cluster:
    @bash scripts/stop.sh

# Keep THIS Mac awake: no sleep + caffeinate + high power. For long agent
# loops on the head; the worker gets it automatically. Bare = toggle.
awake mode="toggle":
    @bash scripts/power.sh "{{ mode }}"

alias start := start-ai-cluster
alias stop := stop-ai-cluster

# ---------------------------------------------------------------- cluster

# Live dashboard: nodes, instances, runner states, download progress
watch interval="3":
    @bash scripts/watch.sh "{{ interval }}"

# TTFT + tokens/sec via the same endpoint opencode uses; history -> bench/perf.jsonl
perf model="" tg="128":
    @bash scripts/perf.sh "{{ model }}" "{{ tg }}"

# Nodes + loaded instances
cluster-status:
    @curl -s "$EXO_API/state" | jq '. as $s | { \
        nodes: [$s.topology.nodes[]? | { \
            name: $s.nodeIdentities[.].friendlyName, \
            chip: $s.nodeIdentities[.].chipId, \
            ram_gb: (($s.nodeMemory[.].ramTotal.inBytes // 0) / 1073741824 | floor), \
            free_gb: (($s.nodeMemory[.].ramAvailable.inBytes // 0) / 1073741824 | floor)}], \
        instances: [$s.instances // {} | to_entries[] | { \
            id: .key, \
            model: (.value[]?.shardAssignments.modelId)}] }'

# Is the cluster on RDMA or falling back to TCP ring?
link-check:
    @bash scripts/link-check.sh

# Placement options for a model (Tensor+jaccl = RDMA path)
previews model:
    @curl -s "$EXO_API/instance/previews?model_id={{ model }}" \
      | jq '.previews[] | {sharding, instance_meta, error, mem: .memory_delta_by_node}'

# Load a model, preferring tensor-parallel / RDMA placement
load model:
    @bash scripts/load-model.sh "{{ model }}"

# Unload everything
unload-all:
    @bash scripts/unload-all.sh

# Switch tier config: throughput | advisor
config profile:
    @bash scripts/profile.sh "{{ profile }}"

# Quick smoke test against a loaded model
ask model prompt:
    @curl -sN -X POST "$EXO_API/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -d "$(jq -n --arg m "{{ model }}" --arg p "{{ prompt }}" \
            '{model:$m, messages:[{role:"user",content:$p}], stream:false}')" \
      | jq -r '.choices[0].message.content'

# ---------------------------------------------------------------- shell

# Wire the zsh plugin into antidote + oh-my-zsh (symlink, survives git pull)
zsh-install:
    @bash scripts/zsh-install.sh

# Remove everything zsh-install added
zsh-uninstall:
    @bash scripts/zsh-uninstall.sh

# Time your shell startup — plugin should add ~0ms
zsh-bench:
    @for i in $(seq 1 10); do /usr/bin/time -p zsh -i -c exit; done 2>&1 \
      | awk '/real/{s+=$2; n++} END{printf "  mean startup: %.0f ms over %d runs\n", s/n*1000, n}'

# ---------------------------------------------------------------- projects

# Wire another repo to this cluster. Additive, idempotent, vendors nothing.
# usage: just project-init ~/code/myapp [throughput|advisor]
# Bare or relative dirs resolve against where YOU ran the command, not this repo.
project-init dir="" tier="throughput":
    @INVOKE_DIR="{{ invocation_directory() }}" bash scripts/project-init.sh "{{ dir }}" "{{ tier }}"

# ---------------------------------------------------------------- agents

# Write opencode + codex configs pointing at the cluster
agents:
    @bash scripts/agents.sh

# ---------------------------------------------------------------- rdma

# Print the Recovery Mode steps (can't be automated — by design)
rdma-howto:
    @bash scripts/rdma-howto.sh

# Apply EXO's RDMA network config. DESTRUCTIVE: wipes Thunderbolt Bridge + static IPs.
rdma-apply:
    @bash scripts/rdma-apply.sh

# ---------------------------------------------------------------- bench

# Benchmark a model across placements. Needs exo source checkout (just exo-src)
bench model="gpt-oss-120b" pp="512,2048,8192" tg="256":
    @cd vendor/exo && uv run bench/exo_bench.py \
        --model {{ model }} --pp {{ pp }} --tg {{ tg }} \
        --max-nodes 2 --repeat 3 \
        --json-out "../../bench/$(date +%Y%m%d-%H%M)-{{ model }}.json"

# Clone exo source into vendor/ (needed for bench + rdma script)
exo-src:
    @bash scripts/exo-src.sh

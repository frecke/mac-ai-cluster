# mac-ai-cluster

Two-Mac local inference cluster. Clone on both machines, run `just bootstrap`.

- **head** (M5 Pro 48GB) — coding agent + its share of pooled inference
- **worker** (M4 Pro 48GB) — inference only

Role is auto-detected from the chip (M5 → head, M4 → worker). On any other
hardware pairing, set it explicitly: `cp mise.local.toml.example mise.local.toml`
and edit `NODE_ROLE`.

## Prereqs

Xcode (App Store), Homebrew, and:

```bash
brew install mise just
```

## Setup

```bash
git clone <this repo> && cd mac-ai-cluster
mise trust
just bootstrap     # idempotent, safe to re-run
just doctor        # verify everything
```

`bootstrap` installs tools only. It does **not** touch memory settings or start anything.

## Daily use

```bash
just start-ai-cluster            # throughput tier (default)
just start-ai-cluster advisor    # 120b pooled + 8b tiny
just start-ai-cluster none       # cluster up, no models loaded

just cluster-status
just config advisor              # switch tier without restarting
just ask "$MODEL_FAST" "explain this repo's error handling"

just stop-ai-cluster             # unload, quit EXO, hand memory back
```

Aliases: `just start` / `just stop`.

### Memory is session-scoped

The GPU wired-memory limit is raised only while a session is running, and reset to the
macOS default by `stop-ai-cluster`. Nothing persists across reboot — no LaunchDaemon,
no login items. If you ever installed the persistent version, `just gpu-unpersist`
removes it.

`start-ai-cluster` also disables sleep on the worker; `stop-ai-cluster` re-enables it.

## RDMA (after you have a TB5 cable)

```bash
just doctor        # confirm link is 80/120 Gb/s, not 40
just rdma-howto    # Recovery Mode steps, per machine
just exo-src
just rdma-apply    # DESTRUCTIVE: wipes Thunderbolt Bridge + static IPs
just doctor        # confirm jaccl placements appear
```

## zsh (antidote + oh-my-zsh)

```bash
just zsh-install
exec zsh
```

Symlinks `zsh/` into `$ZSH_CUSTOM/plugins/aicluster` and appends
`path:<repo>/zsh` to `.zsh_plugins.txt`, so `git pull` updates the plugin.
Antidote bundles statically — regenerate after adding:

```bash
antidote bundle < ~/.zsh_plugins.txt > ~/.zsh_plugins.zsh
```

Commands work from any directory:

| | |
|---|---|
| `aic` | list recipes (tab-completes) |
| `aic <recipe>` | run any recipe |
| `aiup [profile]` | start-ai-cluster |
| `aidown` | stop-ai-cluster |
| `aistat` / `aidoc` / `ailink` | status / doctor / link-check |
| `aicd` | cd to the repo |
| `aicinit [tier]` | wire the current project to the cluster |

Optional prompt segment (oh-my-zsh `*_prompt_info` convention):

```zsh
AICLUSTER_PROMPT=1
RPROMPT='$(aicluster_prompt_info)'   # shows: [ai 2n/1m]
```

Startup cost is ~0ms: no network calls or subprocesses at load, `zsh-defer`
used if present, and cluster state cached for 15s (`AICLUSTER_STATE_TTL`)
with a 1s hard timeout so a sleeping worker never stalls your prompt.
Verify with `just zsh-bench`.

## Using the cluster from other projects

The cluster is **ambient infrastructure** — cloned once per machine, not vendored
per repo. `aic` resolves this repo from the zsh plugin's own path, so it works
from inside any project directory.

To wire a project to it:

```bash
cd ~/code/myapp
aicinit                 # or: aicinit advisor
```

That adds three small things, all additive and idempotent, backing up anything
it appends to:

| file | what |
|---|---|
| `mise.toml` | `EXO_API`, `AI_TIER`, `AI_MODEL` + `mise run ai` / `ai:up` tasks |
| `AGENTS.md` | a section telling coding agents the endpoint and default model |
| `opencode.json` | project default model, merged over your global config |

Nothing is copied from this repo. Change a model name here and every project
follows, because they reference the tier, not a pinned copy.

## Background

[docs/SETUP.md](docs/SETUP.md) — why EXO over Ollama/llama.cpp RPC, the RDMA decision,
model sizing math, and the failure modes worth knowing about.

## Bench

```bash
just exo-src
just bench gpt-oss-120b
```

Long prompts are what matter — `--pp 8192` reflects real agent workloads far better
than the short-prompt numbers everyone publishes.

## Layout

```
mise.toml           tool versions + model tier env
justfile            all recipes
scripts/            implementation, sourced by just
  doctor.sh         the one that verifies everything
  role.sh           chip -> role detection
  start.sh          session up: memory, EXO, model tier
  stop.sh           session down: unload, quit, reset memory
  gpu-wired.sh      session-scoped wired memory limit
zsh/                antidote + oh-my-zsh plugin
templates/          drop-ins rendered into other repos by project-init
vendor/exo          exo source (gitignored, for bench + rdma script)
```

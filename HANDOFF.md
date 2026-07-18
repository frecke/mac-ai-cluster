# Handoff — publishing this repo

Context for a fresh Claude Code session. Delete this file once the repo is up.

## What this is

A two-Mac local inference cluster, built over a design conversation. Not a
generic template — decisions were made deliberately:

- **EXO, not Ollama.** Ollama has no distributed inference (ollama#5983 still
  open). "Ollama clusters" are load balancers over N independent instances —
  throughput, not pooled memory.
- **EXO, not llama.cpp RPC.** RPC works and is the documented fallback in
  `docs/SETUP.md`, but it's pipeline-only and adds a network round trip per
  decode step. EXO does tensor-parallel over RDMA on macOS 26.2+.
- **Memory is session-scoped, never persistent.** `iogpu.wired_limit_mb` is
  raised by `start-ai-cluster` and reset by `stop-ai-cluster`. An earlier
  version used a LaunchDaemon; `just gpu-unpersist` cleans that up.
- **The cluster is ambient, not vendored.** Cloned once per machine. Other
  repos get wired to it via `just project-init` / `aicinit`, which writes a
  few lines of config and copies nothing.

## Hardware it was written against

| | |
|---|---|
| head | MacBook Pro 14" 2026, M5 Pro, 48GB |
| worker | MacBook Pro 14" 2024, M4 Pro, 48GB |
| link | Thunderbolt (TB5 required for RDMA) |
| OS | macOS 26.2+ on both, build strings must match exactly |

Role is auto-detected from the chip in `scripts/role.sh` (M5 → head, M4 →
worker), overridable with `NODE_ROLE`. **If publishing, this is the most
machine-specific assumption in the repo** — consider a config file instead.

## Known-untested

Written and reviewed but never executed:

- `zsh/aicluster.plugin.zsh` — no zsh available in the authoring environment.
  Parse-checked by eye only. CI now runs `zsh -n`.
- Everything touching `sysctl`, `pmset`, `system_profiler`, `hdiutil` — macOS
  only. `scripts/project-init.sh` was functionally tested against a fake repo.
- Model IDs in `mise.toml` are plausible but unverified against EXO's model
  registry. Check with `curl $EXO_API/models` before trusting them.

## Tasks for this session

1. `git init`, initial commit, push to GitHub as a **public** repo.
2. Verify CI passes; fix any real shellcheck errors it surfaces.
3. Sanity-check the model IDs against a running EXO instance.
4. Consider replacing chip-based role detection with an explicit config file
   before other people use this.
5. Delete this file.

## Repo map

```
justfile              all recipes — start here
mise.toml             tool versions + model tier definitions
scripts/
  doctor.sh           verifies everything; the best entry point for reading
  start.sh stop.sh    session lifecycle
  role.sh             chip -> role
  project-init.sh     wire another repo to the cluster
zsh/                  antidote + oh-my-zsh plugin
templates/            rendered into other repos by project-init
docs/SETUP.md         the long-form reasoning + llama.cpp RPC fallback
```

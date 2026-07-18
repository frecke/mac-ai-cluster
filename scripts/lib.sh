#!/usr/bin/env bash
# Shared helpers. Source, don't execute.

set -euo pipefail

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; DIM=$'\033[2m'; BLD=$'\033[1m'; RST=$'\033[0m'

PASS=0; WARN=0; FAIL=0

ok()   { printf "  ${GRN}✓${RST} %s\n" "$*"; PASS=$((PASS+1)); }
warn() { printf "  ${YLW}!${RST} %s\n" "$*"; WARN=$((WARN+1)); }
bad()  { printf "  ${RED}✗${RST} %s\n" "$*"; FAIL=$((FAIL+1)); }
note() { printf "    ${DIM}%s${RST}\n" "$*"; }
hdr()  { printf "\n${BLD}%s${RST}\n" "$*"; }

summary() {
  printf "\n${BLD}%d passed, %d warnings, %d failed${RST}\n" "$PASS" "$WARN" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

EXO_API="${EXO_API:-http://localhost:52415}"

# Fallbacks so scripts work even if mise env isn't activated in this shell.
MODEL_FAST="${MODEL_FAST:-Qwen3-Coder-30B-A3B-Instruct-4bit}"
MODEL_TINY="${MODEL_TINY:-Qwen3-8B-4bit}"
MODEL_BIG="${MODEL_BIG:-gpt-oss-120b}"

chip() { sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown; }
ram_gb() { echo $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )); }
have() { command -v "$1" >/dev/null 2>&1; }
exo_up() { curl -sf --max-time 2 "$EXO_API/state" >/dev/null 2>&1; }

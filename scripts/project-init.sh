#!/usr/bin/env bash
# Drop cluster wiring into another repo. Additive and idempotent.
# usage: project-init.sh [target-dir] [tier]
cd "$(dirname "$0")/.."; source scripts/lib.sh
ROOT="$(pwd -P)"
TARGET="$(cd "${1:-$PWD}" && pwd -P)"
TIER="${2:-throughput}"

[ "$TARGET" = "$ROOT" ] && { bad "that's the cluster repo itself"; exit 1; }

case "$TIER" in
  throughput) MODEL="$MODEL_FAST" ;;
  advisor)    MODEL="$MODEL_BIG"  ;;
  *) bad "tier must be throughput or advisor"; exit 1 ;;
esac

hdr "Wiring $(basename "$TARGET") -> local cluster  ${DIM}(tier=$TIER)${RST}"

render() { sed -e "s|{{MODEL}}|$MODEL|g" -e "s|{{TIER}}|$TIER|g" \
               -e "s|{{API}}|$EXO_API|g" -e "s|{{ROOT}}|$ROOT|g" "$1"; }

# 1. mise config — append to existing, never clobber
MT="$TARGET/mise.toml"; [ -f "$TARGET/.mise.toml" ] && MT="$TARGET/.mise.toml"
if [ -f "$MT" ] && grep -q 'EXO_API' "$MT"; then
  ok "$(basename "$MT") already wired"
elif [ -f "$MT" ]; then
  cp "$MT" "$MT.bak.$(date +%Y%m%d-%H%M%S)"
  printf '\n' >> "$MT"; render templates/aicluster.mise.toml >> "$MT"
  ok "appended to $(basename "$MT") (backup kept)"
else
  render templates/aicluster.mise.toml > "$MT"
  ok "created $(basename "$MT")"
fi

# 2. AGENTS.md — only if absent; otherwise append a section
AG="$TARGET/AGENTS.md"
if [ ! -f "$AG" ]; then
  render templates/AGENTS.md > "$AG"; ok "created AGENTS.md"
elif grep -q 'aic start-ai-cluster' "$AG"; then
  ok "AGENTS.md already documents the cluster"
else
  printf '\n' >> "$AG"
  render templates/AGENTS.md | sed '1,2d' >> "$AG"
  ok "appended cluster section to AGENTS.md"
fi

# 3. opencode project override — merged over your global config
OC="$TARGET/opencode.json"
if [ -f "$OC" ]; then
  ok "opencode.json exists — left alone"
else
  jq -n --arg m "$MODEL" '{"$schema":"https://opencode.ai/config.json", model:("exo/"+$m)}' > "$OC"
  ok "created opencode.json (defaults to $MODEL)"
fi

cat <<TXT

  ${DIM}Nothing was vendored — the cluster stays at $ROOT${RST}

  cd $TARGET
  mise trust && aic start-ai-cluster $TIER
  opencode

TXT

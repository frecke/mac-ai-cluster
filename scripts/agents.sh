#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
FAST="$MODEL_FAST"; BIG="$MODEL_BIG"; TINY="$MODEL_TINY"

mkdir -p ~/.config/opencode
OPENCODE_CONFIG=~/.config/opencode/opencode.json
NEW_OPENCODE="$(jq -n --arg u "$EXO_API/v1" --arg f "$FAST" --arg b "$BIG" --arg t "$TINY" '{
  "$schema": "https://opencode.ai/config.json",
  provider: { exo: {
    npm: "@ai-sdk/openai-compatible",
    name: "EXO Cluster",
    options: { baseURL: $u },
    models: {
      ($f): { name: "Workhorse 30b" },
      ($b): { name: "Advisor 120b (pooled)" },
      ($t): { name: "Tiny 8b" }
    }}}}')"
if [ -f "$OPENCODE_CONFIG" ] && ! diff -q <(printf '%s\n' "$NEW_OPENCODE") "$OPENCODE_CONFIG" >/dev/null 2>&1; then
  BAK="$OPENCODE_CONFIG.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$OPENCODE_CONFIG" "$BAK"
  warn "existing opencode config differs — backed up -> $BAK"
fi
printf '%s\n' "$NEW_OPENCODE" > "$OPENCODE_CONFIG"
ok "opencode -> $OPENCODE_CONFIG"

mkdir -p ~/.codex
cat > ~/.codex/config.toml <<TOML
model = "$BIG"
model_provider = "exo"

[model_providers.exo]
name = "EXO"
base_url = "$EXO_API/v1"
wire_api = "chat"
TOML
ok "codex -> ~/.codex/config.toml"

cat > "$PWD/.envrc.claude" <<ENVRC
# source this to point Claude Code at the cluster
export ANTHROPIC_BASE_URL=$EXO_API
export ANTHROPIC_AUTH_TOKEN=dummy
export ANTHROPIC_MODEL=$BIG
ENVRC
ok "claude code -> source .envrc.claude"

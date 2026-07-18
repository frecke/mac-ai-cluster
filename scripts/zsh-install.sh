#!/usr/bin/env bash
# Wire the zsh plugin into antidote and/or oh-my-zsh.
# Touches exactly two things, both reversible with `just zsh-uninstall`:
#   1. a symlink at $ZSH_CUSTOM/plugins/aicluster
#   2. one appended line in .zsh_plugins.txt (backed up first)
cd "$(dirname "$0")/.."; source scripts/lib.sh
ROOT="$(pwd -P)"
PLUGIN="$ROOT/zsh"

# ── conflict check ────────────────────────────────────────────────────
# Every name this plugin defines. If your setup already uses one, stop
# rather than silently shadowing it.
NAMES="aic aicd aiup aidown aistat aidoc ailink aicluster_prompt_info"
hdr "Checking for name collisions in your current shell"

CONFLICTS=""
for n in $NAMES; do
  W=$(zsh -ic "whence -w $n" 2>/dev/null | head -1) || true
  if [ -n "$W" ] && ! printf '%s' "$W" | grep -q 'none$'; then
    CONFLICTS="$CONFLICTS $n"
    bad "$W"
  fi
done

if [ -n "$CONFLICTS" ]; then
  warn "those names already exist in your shell"
  note "the plugin would shadow them. Rename yours, or edit the alias block"
  note "in zsh/aicluster.plugin.zsh, then re-run. Nothing has been changed."
  exit 1
fi
ok "no collisions"

# ── oh-my-zsh custom plugin ───────────────────────────────────────────
hdr "oh-my-zsh"
OMZ_CUSTOM="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}"
if [ -d "$OMZ_CUSTOM" ]; then
  mkdir -p "$OMZ_CUSTOM/plugins"
  TARGET="$OMZ_CUSTOM/plugins/aicluster"
  if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    bad "$TARGET exists and is not a symlink — refusing to overwrite"; exit 1
  fi
  ln -sfn "$PLUGIN" "$TARGET"
  ok "symlinked -> $TARGET"
  note "classic OMZ loading? add 'aicluster' to plugins=(...) in .zshrc"
  note "antidote loading OMZ for you? skip that — the line below is what matters"
else
  note "no oh-my-zsh custom dir — skipping (fine if antidote loads OMZ for you)"
fi

# ── antidote bundle ───────────────────────────────────────────────────
hdr "antidote"
ZP="${ZDOTDIR:-$HOME}/.zsh_plugins.txt"
LINE="$PLUGIN"
if [ -f "$ZP" ]; then
  if grep -qF "$LINE" "$ZP"; then
    ok "already present in $ZP"
  else
    BAK="$ZP.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$ZP" "$BAK"
    ok "backed up -> $BAK"
    printf '\n# local: two-Mac inference cluster (just zsh-uninstall to remove)\n%s\n' "$LINE" >> "$ZP"
    ok "appended 1 line to $ZP"
  fi
  warn "antidote bundles statically — regenerate before it takes effect:"
  note "antidote bundle < $ZP > \${ZDOTDIR:-\$HOME}/.zsh_plugins.zsh"
else
  note "no $ZP found. Add this line to your antidote bundle file:"
  printf '\n    %s\n' "$LINE"
fi

cat <<TXT

  Reload:  exec zsh
  Verify:  aic            (should list recipes)
  Undo:    just zsh-uninstall

  Commands, from any directory:
    aic                 list recipes (tab-completes)
    aiup [profile]      start-ai-cluster
    aidown              stop-ai-cluster
    aistat / aidoc      status / doctor
    aicd                cd to the repo

  Optional prompt segment — add to .zshrc:
    AICLUSTER_PROMPT=1
    RPROMPT='\$(aicluster_prompt_info)'

TXT

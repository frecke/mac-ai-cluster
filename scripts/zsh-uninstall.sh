#!/usr/bin/env bash
# Full undo of zsh-install. Leaves your shell exactly as it was.
cd "$(dirname "$0")/.."; source scripts/lib.sh
ROOT="$(pwd -P)"; PLUGIN="$ROOT/zsh"

OMZ_CUSTOM="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}"
T="$OMZ_CUSTOM/plugins/aicluster"
if [ -L "$T" ]; then rm -f "$T"; ok "removed symlink $T"
else note "no OMZ symlink"; fi

ZP="${ZDOTDIR:-$HOME}/.zsh_plugins.txt"
if [ -f "$ZP" ] && grep -qF "path:$PLUGIN" "$ZP"; then
  cp "$ZP" "$ZP.bak.$(date +%Y%m%d-%H%M%S)"
  grep -vF -e "path:$PLUGIN" -e "# local: two-Mac inference cluster" "$ZP" > "$ZP.new"
  mv "$ZP.new" "$ZP"
  ok "removed the line from $ZP (backup kept)"
else
  note "nothing to remove from $ZP"
fi

rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/aicluster" && ok "cleared plugin cache"

warn "regenerate the antidote bundle, then: exec zsh"
note "antidote bundle < $ZP > \${ZDOTDIR:-\$HOME}/.zsh_plugins.zsh"
note "if you added 'aicluster' to plugins=(...) in .zshrc, remove it manually"

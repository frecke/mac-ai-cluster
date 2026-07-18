# aicluster — zsh plugin for the two-Mac inference cluster
#
# antidote:   echo 'path:~/code/mac-ai-cluster/zsh' >> ~/.zsh_plugins.txt
# oh-my-zsh:  just zsh-install   (symlinks into $ZSH_CUSTOM/plugins)
#
# Design rule: no network calls and no subprocesses at load time.
# Everything expensive is lazy or cached. This must not cost you shell startup.

(( ${+AICLUSTER_LOADED} )) && return 0
typeset -g AICLUSTER_LOADED=1

# Repo root resolved from this file's own path — no git call, no cwd guess.
typeset -g AICLUSTER_ROOT="${0:A:h:h}"
typeset -g AICLUSTER_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/aicluster"
typeset -g AICLUSTER_API="${EXO_API:-http://localhost:52415}"
typeset -g AICLUSTER_STATE_TTL="${AICLUSTER_STATE_TTL:-15}"   # seconds

# Prompt styling — plain vars, not inline ${:-} defaults, because the values
# contain braces that are painful to escape inside a parameter expansion.
: ${ZSH_THEME_AICLUSTER_PREFIX="%F{cyan}["}
: ${ZSH_THEME_AICLUSTER_SUFFIX="]%f"}

# Builtin modules the state cache depends on. ~0.1ms, and loading them here
# rather than in _aicluster_init avoids a race when init is deferred but the
# prompt segment fires first.
zmodload -F zsh/stat b:zstat 2>/dev/null
zmodload zsh/datetime 2>/dev/null

[[ -d $AICLUSTER_CACHE ]] || command mkdir -p $AICLUSTER_CACHE

# ─────────────────────────────────────────────────────────────── core

_aicluster_just() {
  command just --justfile "$AICLUSTER_ROOT/justfile" \
               --working-directory "$AICLUSTER_ROOT" "$@"
}

# Run any recipe from anywhere. Invalidates cached state on mutating recipes.
aic() {
  if (( $# == 0 )); then
    _aicluster_just --list --unsorted
    return
  fi
  _aicluster_just "$@"
  local rc=$?
  case ${1} in
    start*|stop*|config|load|unload-all) _aicluster_invalidate ;;
  esac
  return $rc
}

aicd() { builtin cd -- "$AICLUSTER_ROOT" }

alias aiup='aic start-ai-cluster'
alias aidown='aic stop-ai-cluster'
alias aistat='aic cluster-status'
alias aidoc='aic doctor'
alias ailink='aic link-check'

# Wire the CURRENT directory's project to the cluster.
aicinit() { aic project-init "$PWD" "${1:-throughput}" }

# ─────────────────────────────────────────────────────────── cached state

# At most one API call per TTL, hard 1s timeout, never blocks the prompt.
_aicluster_state() {
  local f=$AICLUSTER_CACHE/state.json
  local -a mt
  if [[ -f $f ]]; then
    zstat -A mt +mtime $f 2>/dev/null
    if (( ${mt[1]:-0} && EPOCHSECONDS - ${mt[1]} < AICLUSTER_STATE_TTL )); then
      command cat $f
      return 0
    fi
  fi
  if command curl -sf --max-time 1 "$AICLUSTER_API/state" > $f.tmp 2>/dev/null; then
    command mv $f.tmp $f
    command cat $f
  else
    command rm -f $f.tmp
    print -n '{}'
    return 1
  fi
}

_aicluster_invalidate() { command rm -f $AICLUSTER_CACHE/state.json }

# ────────────────────────────────────────────────────── oh-my-zsh prompt

# OMZ themes call *_prompt_info functions. Opt in with:
#   AICLUSTER_PROMPT=1
#   RPROMPT='$(aicluster_prompt_info)'
aicluster_prompt_info() {
  (( ${AICLUSTER_PROMPT:-0} )) || return 0
  (( $+commands[jq] )) || return 0
  local st n m
  st=$(_aicluster_state) || return 0
  n=${$(print -r -- $st | command jq -r '.nodes | length' 2>/dev/null):-0}
  (( n > 0 )) || return 0
  m=${$(print -r -- $st | command jq -r '[.instances[]?.model_id] | length' 2>/dev/null):-0}
  print -n "${ZSH_THEME_AICLUSTER_PREFIX}ai ${n}n/${m}m${ZSH_THEME_AICLUSTER_SUFFIX}"
}

# ─────────────────────────────────────────────────────────── completion

# just's own completions, regenerated only when the just binary changes.
_aicluster_just_comp() {
  local f=$AICLUSTER_CACHE/_just
  (( $+commands[just] )) || return
  if [[ ! -f $f || $commands[just] -nt $f ]]; then
    command just --completions zsh > $f 2>/dev/null || return
  fi
  fpath=($AICLUSTER_CACHE $fpath)
}

_aic() {
  local -a recipes
  local f=$AICLUSTER_CACHE/recipes
  if [[ ! -f $f || $AICLUSTER_ROOT/justfile -nt $f ]]; then
    _aicluster_just --summary 2>/dev/null | tr ' ' '\n' > $f
  fi
  # (f) on a trailing newline yields a stray empty element — ${arr:#} drops it.
  recipes=(${(f)"$(<$f)"})
  recipes=(${recipes:#})

  if (( CURRENT == 2 )); then
    _describe -t recipes 'recipe' recipes
    return
  fi

  local -a profiles=(throughput advisor none)

  case ${words[2]} in
    # project-init takes <dir> <tier> — directory first, tier second.
    project-init)
      if (( CURRENT == 3 )); then _files -/
      else _describe -t profiles 'tier' profiles; fi ;;
    start-ai-cluster|config)
      _describe -t profiles 'profile' profiles ;;
    load|previews|ask|bench)
      local -a models
      models=(${(f)"$(_aicluster_state | command jq -r '.instances[]?.model_id' 2>/dev/null)"})
      models=(${models:#})   # drop empties, else $#models is 1 when nothing loaded
      (( $#models )) || models=(
        "${MODEL_FAST:-Qwen3-Coder-30B-A3B-Instruct-4bit}"
        "${MODEL_TINY:-Qwen3-8B-4bit}"
        "${MODEL_BIG:-gpt-oss-120b}"
      )
      _describe -t models 'model' models ;;
  esac
}

# ─────────────────────────────────────────────────────────────── init

_aicluster_init() {
  _aicluster_just_comp
  (( $+functions[compdef] )) && compdef _aic aic
}

# Defer if zsh-defer is present (common alongside antidote), else run inline.
if (( $+functions[zsh-defer] )); then
  zsh-defer _aicluster_init
else
  _aicluster_init
fi

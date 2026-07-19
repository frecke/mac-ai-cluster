#!/usr/bin/env bash
# just doctor — verify everything, change nothing.
cd "$(dirname "$0")/.."
source scripts/lib.sh

ROLE="$(bash scripts/role.sh)"

printf "${BLD}Cluster doctor${RST}  ${DIM}%s · %s · %sGB · role=%s${RST}\n" \
  "$(scutil --get LocalHostName 2>/dev/null || hostname -s)" "$(chip)" "$(ram_gb)" "$ROLE"

# ─────────────────────────────────────────────────────────── platform
hdr "Platform"

OS_VER="$(sw_vers -productVersion)"; OS_BUILD="$(sw_vers -buildVersion)"
if [ "$(printf '%s\n26.2\n' "$OS_VER" | sort -V | head -1)" = "26.2" ]; then
  ok "macOS $OS_VER ($OS_BUILD)"
else
  bad "macOS $OS_VER — need 26.2+ for RDMA and the EXO app"
fi
note "peer must report build $OS_BUILD exactly — mismatched builds break RDMA discovery"

if [ "$(ram_gb)" -ge 32 ]; then ok "$(ram_gb) GB unified memory"; else warn "$(ram_gb) GB — tight"; fi

XC="$(xcode-select -p 2>/dev/null || true)"
case "$XC" in
  *Xcode.app*) ok "Xcode toolchain active" ;;
  *CommandLineTools*) bad "CLT active, not Xcode — MLX needs the Metal toolchain"
                      note "fix: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" ;;
  *) bad "no developer dir set" ;;
esac

# ─────────────────────────────────────────────────────────── toolchain
hdr "Toolchain"

for t in mise just uv node jq cargo rustc; do
  if have "$t"; then
    ok "$t $("$t" --version 2>/dev/null | head -1 | grep -oE '[vV]?[0-9]+(\.[0-9]+)+(-[A-Za-z0-9]+)?' | head -1)"
  else bad "$t missing"; fi
done

if have macmon; then
  MM_PATH="$(command -v macmon)"
  case "$MM_PATH" in
    *"/.cargo/bin/"*) ok "macmon (cargo build — correct)" ;;
    *) if [[ "$(chip)" == *"M5"* ]]; then
         bad "macmon from $MM_PATH — Homebrew build segfaults on M5"
         note "fix: just macmon"
       else warn "macmon from $MM_PATH — prefer the pinned fork for version parity"; fi ;;
  esac
else
  bad "macmon missing — EXO uses it for telemetry (just macmon)"
fi

# ─────────────────────────────────────────────────────────── memory
hdr "GPU memory"

WIRED="$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)"
EXPECT="$(bash scripts/gpu-wired.sh "$ROLE" --print-only)"
if [ "$WIRED" -eq 0 ]; then
  note "wired limit at macOS default (~75% = $(( $(ram_gb) * 3 / 4 ))GB) — session not started"
  note "raised to ${EXPECT}MB by: just start-ai-cluster"
elif [ "$WIRED" -ge "$EXPECT" ]; then
  ok "wired limit ${WIRED}MB (target ${EXPECT}MB for $ROLE) — session active"
else
  warn "wired limit ${WIRED}MB below target ${EXPECT}MB"
fi

if [ -f /Library/LaunchDaemons/local.gpuwired.plist ]; then
  warn "persistent wired-limit LaunchDaemon found — this repo manages memory per session now"
  note "remove it: just gpu-unpersist"
else
  ok "no persistent memory override (session-scoped by design)"
fi

FREE_GB=$(( $(df -k / | awk 'NR==2{print $4}') / 1024 / 1024 ))
if [ "$FREE_GB" -ge 150 ]; then ok "${FREE_GB}GB disk free"
elif [ "$FREE_GB" -ge 80 ]; then warn "${FREE_GB}GB disk free — a 120b model is ~63GB per node"
else bad "${FREE_GB}GB disk free — not enough for the big tier"; fi

# ─────────────────────────────────────────────────────────── interconnect
hdr "Thunderbolt link"

TB="$(system_profiler SPThunderboltDataType 2>/dev/null || true)"
LINK_SPEED="$(echo "$TB" | grep -A1 'Link Status: 0x2' | grep -i 'Speed:' | head -1 | sed 's/.*Speed: *//')"
PORT_MAX="$(echo "$TB" | grep -i 'Speed:' | grep -o '[0-9]\+ Gb/s' | sort -rn | head -1)"

if [ -z "$LINK_SPEED" ]; then
  warn "no active Thunderbolt device link detected"
  note "is the cable seated? is the peer awake?"
else
  case "$LINK_SPEED" in
    *120*|*80*) ok "active link: $LINK_SPEED — TB5, RDMA-capable" ;;
    *40*)       bad "active link: $LINK_SPEED — TB4 cable, RDMA will not negotiate"
                note "ports max at ${PORT_MAX:-?}, so it's the cable, not the Macs"
                note "fix: Apple TB5 Pro Cable 1m (MDW94AM/A) or OWC equivalent" ;;
    *)          warn "active link: $LINK_SPEED" ;;
  esac
fi

if ioreg -l 2>/dev/null | grep -qi rdma; then ok "RDMA present in IORegistry"
else warn "RDMA not enabled — needs 'rdma_ctl enable' in Recovery (just rdma-howto)"; fi

# ─────────────────────────────────────────────────────────── exo
hdr "EXO"

if [ -d /Applications/EXO.app ]; then ok "EXO.app installed"
else bad "EXO.app not found (just exo-install)"; fi

if exo_up; then
  ok "API reachable at $EXO_API"

  NODES="$(curl -s "$EXO_API/state" | jq '.nodes | length')"
  case "$NODES" in
    0|1) warn "$NODES node visible — peer not clustered"
         note "check: same EXO_LIBP2P_NAMESPACE, same OS build, peer awake" ;;
    *)   ok "$NODES nodes clustered" ;;
  esac

  META="$(curl -s "$EXO_API/instance/previews?model_id=mlx-community/Llama-3.2-1B-Instruct-4bit" 2>/dev/null \
          | jq -r '[.previews[]? | select(.error==null) | .instance_meta] | unique | join(",")' 2>/dev/null || echo "")"
  case "$META" in
    *jaccl*) ok "jaccl placement available — RDMA transport live" ;;
    *Ring*|*ring*) warn "only TCP ring placements — running without RDMA" ;;
    *) [ "$NODES" -gt 1 ] && warn "could not determine transport" || true ;;
  esac

  LOADED="$(curl -s "$EXO_API/state" | jq -r '[.instances[]?.model_id] | join(", ")')"
  if [ -n "$LOADED" ]; then ok "loaded: $LOADED"; else note "no models loaded (just config throughput)"; fi
else
  bad "API unreachable at $EXO_API — is EXO running?"
fi

# ─────────────────────────────────────────────────────────── power
hdr "Power"

if [ "$ROLE" = "worker" ]; then
  if pmset -g 2>/dev/null | grep -q 'SleepDisabled.*1'; then ok "sleep disabled (session active)"
  elif exo_up; then warn "EXO is running but worker can sleep — it will drop mid-inference"
  else note "sleep enabled — normal while stopped"; fi

  AICACHE="${XDG_CACHE_HOME:-$HOME/.cache}/aicluster"
  if [ -f "$AICACHE/caffeinate.pid" ] && kill -0 "$(cat "$AICACHE/caffeinate.pid")" 2>/dev/null; then
    ok "caffeinate active (pid $(cat "$AICACHE/caffeinate.pid"))"
  elif exo_up; then warn "caffeinate not running — start-ai-cluster starts it"
  else note "caffeinate not running — normal while stopped"; fi

  if pmset -g 2>/dev/null | grep -qE 'powermode +2'; then ok "high power mode"
  elif pmset -g 2>/dev/null | grep -q powermode; then
    if exo_up; then warn "power mode not high — start-ai-cluster sets it"
    else note "power mode automatic — normal while stopped"; fi
  fi
fi
if pmset -g ps 2>/dev/null | grep -qi 'AC Power'; then ok "on AC power"; else warn "on battery — expect throttling"; fi

# ─────────────────────────────────────────────────────────── agents
hdr "Agent configs"

if [ -f ~/.config/opencode/opencode.json ]; then ok "opencode configured"; else warn "opencode not configured (just agents)"; fi
if [ -f ~/.codex/config.toml ]; then ok "codex configured"; else note "codex not configured (just agents)"; fi

summary

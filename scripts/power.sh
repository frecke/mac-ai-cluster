#!/usr/bin/env bash
# Keep-awake power posture: no sleep + caffeinate + high power mode.
# usage: power.sh <on|off|toggle>
# Worker gets this automatically from start/stop-ai-cluster. On the head,
# `just awake` toggles it for long agent loops — it survives stop-ai-cluster
# and stays on until you toggle it off.
# "on" saves the current powermode and restores it on "off" — we borrow the
# setting for the session, we don't own it.
cd "$(dirname "$0")/.."; source scripts/lib.sh
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/aicluster"
mkdir -p "$CACHE"

powermode_supported() { pmset -g 2>/dev/null | grep -q powermode; }
current_powermode() { pmset -g 2>/dev/null | awk '/powermode/{print $2; exit}'; }
caffeinate_alive() {
  # comm check guards against PID reuse after a reboot
  [ -f "$CACHE/caffeinate.pid" ] \
    && ps -p "$(cat "$CACHE/caffeinate.pid")" -o comm= 2>/dev/null | grep -q caffeinate
}

power_on() {
  sudo pmset -a disablesleep 1 && ok "sleep disabled"

  if powermode_supported; then
    # Only save prev on the first "on" — a re-run must not overwrite the
    # real pre-session value with our own 2.
    [ -f "$CACHE/powermode.prev" ] || current_powermode > "$CACHE/powermode.prev"
    sudo pmset -a powermode 2 && ok "high power mode on (was $(cat "$CACHE/powermode.prev"))"
  else
    note "power mode not supported on this machine — skipping"
  fi

  if caffeinate_alive; then
    ok "caffeinate already running (pid $(cat "$CACHE/caffeinate.pid"))"
  else
    # -d display, -i idle, -m disk, -s system (AC) — belt and braces on
    # top of disablesleep; also covers lid-closed on AC.
    nohup caffeinate -dims >/dev/null 2>&1 &
    echo $! > "$CACHE/caffeinate.pid"
    ok "caffeinate running (pid $(cat "$CACHE/caffeinate.pid"))"
  fi
}

power_off() {
  if [ -f "$CACHE/caffeinate.pid" ]; then
    kill "$(cat "$CACHE/caffeinate.pid")" 2>/dev/null || true
    rm -f "$CACHE/caffeinate.pid"
    ok "caffeinate stopped"
  else
    note "caffeinate was not running"
  fi

  if powermode_supported && [ -f "$CACHE/powermode.prev" ]; then
    PREV="$(cat "$CACHE/powermode.prev")"
    sudo pmset -a powermode "${PREV:-0}" && ok "power mode restored (${PREV:-0})"
    rm -f "$CACHE/powermode.prev"
  fi

  sudo pmset -a disablesleep 0 && ok "sleep re-enabled"
}

case "${1:-toggle}" in
  on)  power_on ;;
  off) power_off ;;
  toggle)
    if caffeinate_alive; then
      note "keep-awake is on — turning off"
      power_off
    else
      note "keep-awake is off — turning on"
      power_on
    fi
    ;;
  *) bad "usage: power.sh <on|off|toggle>"; exit 1 ;;
esac

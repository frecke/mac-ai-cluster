#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
P=/Library/LaunchDaemons/local.gpuwired.plist
[ -f "$P" ] || { ok "no persistent wired-limit daemon installed"; exit 0; }
sudo launchctl bootout system/local.gpuwired 2>/dev/null || true
sudo rm -f "$P"
ok "removed persistent wired-limit LaunchDaemon"

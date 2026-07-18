#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
OS="$(sw_vers -productVersion)"
[ "$(printf '%s\n26.2\n' "$OS" | sort -V | head -1)" = "26.2" ] || {
  bad "macOS $OS — need 26.2+"; exit 1; }
ok "macOS $OS ($(sw_vers -buildVersion))"
printf "\n${YLW}Record this build string and confirm it matches the other Mac.${RST}\n\n"

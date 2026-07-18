#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh

XC="$(xcode-select -p 2>/dev/null || true)"
if [[ "$XC" != *Xcode.app* ]]; then
  [ -d /Applications/Xcode.app ] || { bad "Install Xcode from the App Store first"; exit 1; }
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
fi
ok "Xcode toolchain active"

have mise || { bad "install mise first: brew install mise"; exit 1; }
mise trust --yes . >/dev/null 2>&1 || true
mise install
ok "mise tools installed (node, uv, jq, rust-nightly)"

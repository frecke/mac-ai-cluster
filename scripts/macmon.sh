#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
PIN=a1cd06b6cc0d5e61db24fd8832e74cd992097a7d
if [[ "$(command -v macmon || true)" == *"/.cargo/bin/"* ]]; then
  ok "pinned macmon already installed"; exit 0
fi
have brew && brew list macmon >/dev/null 2>&1 && {
  warn "removing Homebrew macmon (segfaults on M5)"; brew uninstall macmon || true; }
cargo install --git https://github.com/vladkens/macmon --rev "$PIN" macmon --force
ok "macmon installed from pinned fork"

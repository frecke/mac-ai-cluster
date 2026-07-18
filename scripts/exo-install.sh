#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
if [ -d /Applications/EXO.app ]; then ok "EXO.app already installed"; exit 0; fi
TMP=$(mktemp -d)
curl -fL --progress-bar https://assets.exolabs.net/EXO-latest.dmg -o "$TMP/EXO.dmg"
MP=$(hdiutil attach -nobrowse -readonly "$TMP/EXO.dmg" | awk -F'\t' '/Volumes/{print $NF}' | tail -1)
cp -R "$MP"/EXO.app /Applications/
hdiutil detach "$MP" >/dev/null; rm -rf "$TMP"
ok "EXO.app installed"
warn "open it once, grant permissions, and set namespace to ${EXO_LIBP2P_NAMESPACE:-my-cluster}"

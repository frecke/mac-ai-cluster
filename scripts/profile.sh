#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
bash scripts/unload-all.sh
case "$1" in
  throughput) bash scripts/load-model.sh "${MODEL_FAST}" ;;
  advisor)    bash scripts/load-model.sh "${MODEL_TINY}"
              bash scripts/load-model.sh "${MODEL_BIG}" ;;
  *) bad "usage: just config {throughput|advisor}"; exit 1 ;;
esac

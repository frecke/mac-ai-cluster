#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
mkdir -p vendor
if [ -d vendor/exo/.git ]; then git -C vendor/exo pull --ff-only; else
  git clone --depth 1 https://github.com/exo-explore/exo vendor/exo; fi
(cd vendor/exo/dashboard && npm install && npm run build)
ok "exo source ready in vendor/exo (bench + rdma script available)"

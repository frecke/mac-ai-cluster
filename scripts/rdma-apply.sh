#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
[ -d vendor/exo ] || { bad "run 'just exo-src' first"; exit 1; }
cat <<'TXT'

  DESTRUCTIVE. This disables Thunderbolt Bridge and sets DHCP on TB ports.
  Your static 192.168.99.0/24 addressing and MTU 9000 will be lost.
  (Both become irrelevant — RDMA bypasses the IP stack.)

TXT
read -rp "  Type 'yes' to continue: " a
[ "$a" = "yes" ] || { note "aborted"; exit 1; }
sudo ./vendor/exo/tmp/set_rdma_network_config.sh
ok "RDMA network config applied — run 'just doctor' on both machines"

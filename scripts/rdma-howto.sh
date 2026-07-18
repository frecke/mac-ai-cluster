#!/usr/bin/env bash
cd "$(dirname "$0")/.."; source scripts/lib.sh
cat <<'TXT'

  RDMA enable — per machine, one time. Cannot be scripted (Recovery Mode).

    1. Shut down
    2. Hold power ~10s until boot options appear
    3. Options -> Continue -> Utilities -> Terminal
    4. rdma_ctl enable
    5. Reboot

  Then, on ONE machine:  just rdma-apply

  Prerequisites — verify with `just doctor` first:
    - active TB link at 80 or 120 Gb/s (a TB4 cable will not work)
    - identical sw_vers -buildVersion on both Macs
TXT

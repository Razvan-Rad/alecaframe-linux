#!/usr/bin/env bash
# Optional: stop AlecaFrame's ads. The ads come from one script, https://content.overwolf.com/libs/ads/latest/owads.min.js,
# which AlecaFrame's pages load; if it can't load, the ad code never starts and nothing else depends on it.
# This adds a hosts entry (needs sudo). `adblock.sh remove` undoes it.
set -euo pipefail
LINE='0.0.0.0 content.overwolf.com   # alecaframe-linux adblock'
case "${1:-add}" in
  add)    grep -qF 'alecaframe-linux adblock' /etc/hosts && { echo "already present"; exit 0; }
          echo "$LINE" | sudo tee -a /etc/hosts >/dev/null && echo "added: $LINE (restart Overwolf/Warframe)";;
  remove) sudo sed -i '/alecaframe-linux adblock/d' /etc/hosts && echo "removed";;
  *) echo "usage: $0 [add|remove]" >&2; exit 2;;
esac

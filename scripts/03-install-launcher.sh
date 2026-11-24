#!/usr/bin/env bash
# Step 3 - install the launch wrapper and print the Steam launch option to use.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
need protonhax
mkdir -p "$STATE_DIR"
install -m 755 "$here/wf-aleca.sh" "$STATE_DIR/wf-aleca.sh"
install -m 644 "$here/wf-start.bat" "$STATE_DIR/wf-start.bat"
log "installed to $STATE_DIR"
cat <<MSG

Set Warframe's Steam launch options to:

    protonhax init $STATE_DIR/wf-aleca.sh %command%

First launch only: put the official 'AlecaFrame - Installer.exe' (from alecaframe.com) in
    $STATE_DIR
It is run automatically, inside the game's session, until AlecaFrame's extension is installed.
Launch log: $STATE_DIR/wf-aleca.log
MSG

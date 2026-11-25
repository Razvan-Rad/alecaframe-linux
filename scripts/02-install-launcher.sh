#!/usr/bin/env bash
# Step 2 - install the Warframe launch wrapper and the AlecaFrame launcher, and print how to hook them into Steam.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
mkdir -p "$STATE_DIR"
install -m 755 "$here/wf-aleca.sh" "$STATE_DIR/wf-aleca.sh"
install -m 755 "$here/alecaframe.sh" "$STATE_DIR/alecaframe.sh"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"; mkdir -p "$apps"
cat > "$apps/alecaframe.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=AlecaFrame
Comment=AlecaFrame (Overwolf) inside the running Warframe Proton session
Exec="$STATE_DIR/alecaframe.sh"
Icon=applications-games
Categories=Game;
Terminal=false
DESKTOP
log "installed to $STATE_DIR (+ $apps/alecaframe.desktop)"
cat <<MSG

1. Warframe -> Properties -> Launch Options:

       $STATE_DIR/wf-aleca.sh %command%

2. Steam -> Add a Game -> Add a Non-Steam Game -> tick "AlecaFrame" -> Add Selected Programs.
   Leave its compatibility tool unset (it is a Linux script).

3. Put the official 'AlecaFrame - Installer.exe' (from alecaframe.com) in
       $STATE_DIR
   The first AlecaFrame launch runs it inside the game's session.

Usage: start Warframe, then AlecaFrame (it waits for the game). Stop in Steam closes Overwolf; it also closes on
its own when Warframe exits. Log: $STATE_DIR/alecaframe.log
MSG

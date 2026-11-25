#!/usr/bin/env bash
# AlecaFrame launcher. Add it to Steam as a non-Steam game (no compatibility tool) and start it after Warframe.
#
#   alecaframe.sh                 start Overwolf + AlecaFrame inside the running Warframe session
#                                 (first run: runs 'AlecaFrame - Installer.exe' from the install dir instead)
#   alecaframe.sh run FILE [ARGS] run any Windows program inside the running Warframe session
#                                 (used once to install Overwolf: alecaframe.sh run ~/Downloads/OverwolfSetup.exe)
#
# Needs Warframe started with wf-aleca.sh as its launch option, which enables the steam-runtime launcher service;
# this script joins the game's container through it (same wineserver/user namespace, so Overwolf can see the game).
#
# While Overwolf runs this script stays alive, so Steam shows AlecaFrame as running: pressing Stop in Steam closes
# Overwolf, and Overwolf is also closed automatically once Warframe has exited.
APPID="${WF_APPID:-230410}"
AF_ID=afmcagbpgggkpdkokjhjkllpegnadmkignlonpjm          # AlecaFrame's Overwolf extension id
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HERE/alecaframe.log"

# Steam injects its overlay/runtime libraries into shortcuts; the launch client does not need them.
unset LD_PRELOAD LD_LIBRARY_PATH

find_client() {
  local root d
  for root in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    for d in "$root"/steamapps/common/SteamLinuxRuntime_*/pressure-vessel/bin "$root"/steamapps/common/SteamLinuxRuntime_sniper/pressure-vessel/bin; do
      [ -x "$d/steam-runtime-launch-client" ] && { echo "$d/steam-runtime-launch-client"; return; }
    done
  done
  command -v steam-runtime-launch-client
}
CLIENT="$(find_client)" || { echo "steam-runtime-launch-client not found (is a Steam Linux Runtime installed?)" >&2; exit 1; }

notify() { command -v notify-send >/dev/null && notify-send -a AlecaFrame "AlecaFrame" "$1"; echo "$1"; }
in_game() { "$CLIENT" --inside-app="$APPID" -- "$@"; }

# Run a Windows program in the game's Wine session as a separate app: SteamGameId/SteamAppId=overwolf make winex11
# give its windows WM_CLASS steam_app_overwolf instead of the game's steam_app_<appid>, so the window manager treats
# AlecaFrame and Warframe as two applications (otherwise focus moves between them never re-grab the game's pointer).
inwine() { in_game env SteamGameId=overwolf SteamAppId=overwolf wine "$@"; }

to_win() { local p; p="$(readlink -f "$1")"; printf 'Z:%s' "${p//\//\\}"; }

wait_for_game() {
  local t
  for ((t = 0; t < 180; t += 2)); do
    in_game true 2>/dev/null && return 0
    (( t == 0 )) && notify "Waiting for Warframe to start…"
    sleep 2
  done
  notify "Warframe is not running (or was not started with wf-aleca.sh as its launch option)."
  return 1
}

if [ "${1:-}" = run ]; then
  shift; [ $# -ge 1 ] || { echo "usage: $0 run FILE [ARGS...]" >&2; exit 2; }
  f="$1"; shift; [ -e "$f" ] && f="$(to_win "$f")"
  wait_for_game || exit 1
  exec "$CLIENT" --inside-app="$APPID" -- env SteamGameId=overwolf SteamAppId=overwolf wine "$f" "$@"
fi

exec >>"$LOG" 2>&1; echo "=== $(date)"
wait_for_game || exit 1

OW='C:\\Program Files \(x86\)\\[O]verwolf'           # pgrep -f pattern: Overwolf's Wine processes only
kill_ow() {
  pkill -u "$UID" -f "$OW"
  for _ in 1 2 3 4 5; do pgrep -u "$UID" -f "$OW" >/dev/null || return; sleep 1; done
  pkill -9 -u "$UID" -f "$OW"
}
trap 'echo "stop requested -> closing Overwolf"; kill_ow; exit 0' TERM INT HUP

pfx="$(in_game sh -c 'printf %s "$WINEPREFIX"' 2>/dev/null)"
if [ -n "$pfx" ] && [ ! -d "$pfx/drive_c/users/steamuser/AppData/Local/Overwolf/Extensions/$AF_ID" ]; then
  installer="$HERE/AlecaFrame - Installer.exe"
  [ -f "$installer" ] || { notify "AlecaFrame is not installed yet: put 'AlecaFrame - Installer.exe' in $HERE"; exit 1; }
  echo "AlecaFrame extension missing -> running installer"
  inwine "$(to_win "$installer")"
else
  inwine 'C:\Program Files (x86)\Overwolf\OverwolfLauncher.exe' -launchapp "$AF_ID" -ow-disable-gpu
fi

# Stay alive while Overwolf runs. Close it once Warframe has been gone for 15 s (the launcher -> game hand-off has a
# short gap); otherwise Overwolf keeps the Wine session alive and Steam keeps showing Warframe as running.
for _ in $(seq 30); do pgrep -u "$UID" -f "$OW" >/dev/null && break; sleep 1 & wait $!; done
gone=0
while pgrep -u "$UID" -f "$OW" >/dev/null; do
  if pgrep -u "$UID" -f 'Warframe\.x64\.exe|Warframe\\Tools\\Launcher\.exe' >/dev/null; then gone=0; else ((gone += 2)); fi
  (( gone >= 15 )) && { echo "Warframe exited -> closing Overwolf"; kill_ow; break; }
  sleep 2 & wait $!
done
echo "done"

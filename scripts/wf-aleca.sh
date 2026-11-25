#!/usr/bin/env bash
# Steam launch option for Warframe:
#     <install-dir>/wf-aleca.sh %command%
#
# Starts Warframe normally, but asks Proton to run a steam-runtime "launcher service" inside the game's
# pressure-vessel container. Overwolf has to live in that container (same user namespace as the game's wineserver),
# otherwise Wine denies it access to the game process (EnumProcessModules -> ACCESS_DENIED, Overwolf crashes).
# AlecaFrame is then started separately, from its own Steam shortcut (alecaframe.sh), which uses
# `steam-runtime-launch-client --inside-app=<appid>` to join this container.
export STEAM_COMPAT_LAUNCHER_SERVICE=proton
exec "$@"

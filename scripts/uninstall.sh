#!/usr/bin/env bash
# Undo scripts/03-overwolf-fixes.sh (restores the files it backed up) and 02-install-launcher.sh.
# Does not remove .NET/WebView2 or Overwolf itself.
# Run with Warframe and Overwolf closed.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
detect
refuse_if_running
BK="$STATE_DIR/backup"; SYS="$C/windows/system32"
restore_link() { # name
  if [ -f "$BK/$1.symlink-target" ] && [ -s "$BK/$1.symlink-target" ]; then rm -f "$SYS/$1"; ln -s "$(cat "$BK/$1.symlink-target")" "$SYS/$1"; log "restored $1 symlink"; fi
}
restore_link d3dx11_43.dll
restore_link wintrust.dll
rm -f "$SYS/wintrust_real.dll"
if [ -f "$BK/OverwolfBrowser.exe.orig" ] && OW="$(overwolf_dir)"; then cp "$BK/OverwolfBrowser.exe.orig" "$OW/OverwolfBrowser.exe"; log "restored OverwolfBrowser.exe"; fi
for k in d3dx11_43 wintrust; do w reg delete 'HKCU\Software\Wine\DllOverrides' /v "$k" /f >/dev/null || true; done
wait_wine
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/alecaframe.desktop" "$STATE_DIR/wf-aleca.sh" "$STATE_DIR/alecaframe.sh"
log "done. In Steam: clear Warframe's launch option ('.../wf-aleca.sh %command%') and remove the AlecaFrame shortcut."

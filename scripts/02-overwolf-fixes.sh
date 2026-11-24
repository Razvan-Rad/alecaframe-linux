#!/usr/bin/env bash
# Step 2 - fixes that need Overwolf already installed. Run with Warframe and Overwolf closed.
#   a) d3dx11_43.dll: swap Wine's stub for Microsoft's real DLL (Overwolf ships a copy) so Overwolf's in-game
#      overlay can compile its shaders. Without it the overlay never starts, Overwolf's game-events provider
#      gives up waiting for a renderer, and AlecaFrame reports "No game data".
#   b) OverwolfBrowser.exe entry-point patch + wintrust proxy (see docs/TROUBLESHOOTING.md): without them every
#      Chromium helper process crashes and no Overwolf/AlecaFrame window renders.
# Everything replaced is backed up under ~/.local/share/alecaframe-linux/backup; scripts/uninstall.sh restores it.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
need python3 clang ld.lld llvm-dlltool llvm-readobj
detect
refuse_if_running
OW="$(overwolf_dir)" || die "Overwolf is not installed in this prefix yet (see README, step 'Install Overwolf')"
log "Overwolf: $OW"
BK="$STATE_DIR/backup"
SYS="$C/windows/system32"

# --- a) real d3dx11_43.dll ----------------------------------------------------------------------------------
[ -f "$OW/d3dx11_43.dll" ] || die "Overwolf's d3dx11_43.dll not found in $OW"
if [ -L "$SYS/d3dx11_43.dll" ]; then readlink "$SYS/d3dx11_43.dll" > "$BK/d3dx11_43.symlink-target"; rm "$SYS/d3dx11_43.dll"; fi
cp "$OW/d3dx11_43.dll" "$SYS/d3dx11_43.dll"
reg_add 'HKCU\Software\Wine\DllOverrides' /v d3dx11_43 /d native,builtin
log "d3dx11_43: native copy installed"

# --- b1) entry-point patch for OverwolfBrowser.exe ----------------------------------------------------------
if python3 "$here/patch-overwolf-browser.py" "$OW/OverwolfBrowser.exe" "$BK/OverwolfBrowser.exe.orig"; then :; else
  log "OverwolfBrowser.exe patch skipped (see message above)"; fi

# --- b2) wintrust proxy -------------------------------------------------------------------------------------
build="$(mktemp -d)"; "$here/build-wintrust.sh" "$PROTON_DIR" "$build"
if [ -L "$SYS/wintrust.dll" ]; then readlink "$SYS/wintrust.dll" > "$BK/wintrust.symlink-target"; rm "$SYS/wintrust.dll"; fi
if [ ! -f "$SYS/wintrust_real.dll" ]; then cp "$PROTON_DIR/files/lib/wine/x86_64-windows/wintrust.dll" "$SYS/wintrust_real.dll"; chmod u+w "$SYS/wintrust_real.dll"; fi
cp "$build/wintrust.dll" "$SYS/wintrust.dll"; rm -rf "$build"
reg_add 'HKCU\Software\Wine\DllOverrides' /v wintrust /d native,builtin
wait_wine
log "done. Next: scripts/03-install-launcher.sh"

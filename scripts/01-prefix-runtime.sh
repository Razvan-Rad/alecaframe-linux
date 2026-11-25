#!/usr/bin/env bash
# Step 1 - give Warframe's Proton prefix what Overwolf needs: WebView2 + real .NET Framework 4.8.
# Run with Warframe and Overwolf closed. Safe to re-run (steps already done are skipped).
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"
need curl 7z cabextract python3
detect
refuse_if_running

# --- WebView2 runtime (the Overwolf installer refuses to run without it) -------------------------------
if [ -d "$C/Program Files (x86)/Microsoft/EdgeWebView/Application" ]; then
  log "WebView2 already installed"
else
  fetch "https://go.microsoft.com/fwlink/?linkid=2124701" - "$CACHE_DIR/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
  log "installing WebView2 (silent, ~1 min)"
  w "$CACHE_DIR/MicrosoftEdgeWebView2RuntimeInstallerX64.exe" /silent /install >/dev/null
  wait_wine
fi

# --- .NET Framework 4.8 -----------------------------------------------------------------------------------
# winetricks' dotnet48 chain fails here for two reasons, both fixed below:
#  * Proton ships read-only stub symlinks in Microsoft.NET\Framework*\v4.0.30319 that the installer cannot overwrite.
#  * The 4.8 installer refuses to run when the OS looks like Windows 10 (it assumes 4.8 is built in) -> use win7.
if grep -q '"Release"=dword:00080eb1' "$PFX/system.reg" 2>/dev/null; then
  log ".NET 4.8 already installed"
else
  fetch "https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/ndp48-x86-x64-allos-enu.exe" \
        95889d6de3f2070c07790ad6cf2000d33d9a1bdfc6a381725ab82ab1c314fd53 "$CACHE_DIR/ndp48-x86-x64-allos-enu.exe"
  log "removing Proton's stub symlinks in the .NET 4 directories"
  for d in Framework Framework64; do
    for f in diasymreader.dll fusion.dll ngen.exe; do
      p="$C/windows/Microsoft.NET/$d/v4.0.30319/$f"; [ -L "$p" ] && rm "$p"
    done
  done
  log "installing .NET 4.8 (Windows 7 mode, ~3-5 min)"
  w winecfg -v win7 >/dev/null; wait_wine
  w "$CACHE_DIR/ndp48-x86-x64-allos-enu.exe" /q /norestart >/dev/null; wait_wine
  w winecfg -v win10 >/dev/null; wait_wine
  grep -q '"Release"=dword:00080eb1' "$PFX/system.reg" || die ".NET 4.8 install did not register - see docs/TROUBLESHOOTING.md"
fi

# --- mscoree.dll (the .NET runtime shim) ------------------------------------------------------------------
# The 4.8 installer does not ship mscoree.dll (on real Windows it is part of the OS); the 4.0 installer does.
if [ ! -f "$C/windows/system32/mscoree.dll" ] || [ -L "$C/windows/system32/mscoree.dll" ]; then
  fetch "https://download.microsoft.com/download/9/5/A/95A9616B-7A37-4AF6-BC36-D6EA96C8DAAE/dotNetFx40_Full_x86_x64.exe" \
        65e064258f2e418816b304f646ff9e87af101e4c9552ab064bb74d281c38659f "$CACHE_DIR/dotNetFx40_Full_x86_x64.exe"
  tmp="$(mktemp -d)"; ( cd "$tmp" && 7z x -y -bso0 -bsp0 "$CACHE_DIR/dotNetFx40_Full_x86_x64.exe" >/dev/null 2>&1 || true
                        cabextract -q -F '_003_mscoree_dll_*' netfx_Core.mzz >/dev/null 2>&1 || true )
  [ -f "$tmp/_003_mscoree_dll_amd64" ] || die "could not extract mscoree.dll from the .NET 4.0 installer"
  [ -L "$C/windows/system32/mscoree.dll" ] && rm "$C/windows/system32/mscoree.dll"
  [ -L "$C/windows/syswow64/mscoree.dll" ] && rm "$C/windows/syswow64/mscoree.dll"
  cp "$tmp/_003_mscoree_dll_amd64" "$C/windows/system32/mscoree.dll"
  cp "$tmp/_003_mscoree_dll_x86"   "$C/windows/syswow64/mscoree.dll"
  rm -rf "$tmp"
fi
reg_add 'HKCU\Software\Wine\DllOverrides' /v mscoree /d native
reg_add 'HKLM\Software\Microsoft\.NETFramework' /v InstallRoot /t REG_SZ /d 'C:\windows\Microsoft.NET\Framework64\' /reg:64
reg_add 'HKLM\Software\Microsoft\.NETFramework' /v InstallRoot /t REG_SZ /d 'C:\windows\Microsoft.NET\Framework\'   /reg:32

# --- COM registration for the .NET symbol binder (Overwolf's launcher needs it) --------------------------
w regsvr32 /s 'C:\windows\Microsoft.NET\Framework64\v4.0.30319\diasymreader.dll' >/dev/null
w 'C:\windows\syswow64\regsvr32.exe' /s 'C:\windows\Microsoft.NET\Framework\v4.0.30319\diasymreader.dll' >/dev/null
wait_wine
log "done. Next: scripts/02-install-launcher.sh"

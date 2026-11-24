#!/usr/bin/env bash
# Shared helpers. Source this file; do not run it.
set -euo pipefail

APPID="${WF_APPID:-230410}"   # Warframe's Steam app id
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/alecaframe-linux"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/alecaframe-linux"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"; done; }

# Locate the Warframe Proton prefix (compatdata/<appid>). Override with WF_COMPAT=/path/to/compatdata/230410
find_compat() {
  if [ -n "${WF_COMPAT:-}" ]; then echo "$WF_COMPAT"; return; fi
  local roots=("$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam")
  local root lib vdf
  for root in "${roots[@]}"; do
    [ -d "$root/steamapps" ] || continue
    local libs=("$root")
    vdf="$root/steamapps/libraryfolders.vdf"
    if [ -f "$vdf" ]; then
      while IFS= read -r lib; do libs+=("$lib"); done < <(grep -E '"path"' "$vdf" | sed -E 's/.*"path"[[:space:]]+"([^"]+)".*/\1/')
    fi
    for lib in "${libs[@]}"; do
      if [ -d "$lib/steamapps/compatdata/$APPID/pfx" ]; then echo "$lib/steamapps/compatdata/$APPID"; return; fi
    done
  done
  return 1
}

# Locate the Proton build Warframe runs with. Override with WF_PROTON=/path/to/proton-dir (contains files/bin/wine)
find_proton() {
  if [ -n "${WF_PROTON:-}" ]; then echo "$WF_PROTON"; return; fi
  local d
  for d in /usr/share/steam/compatibilitytools.d/*/ "$HOME"/.local/share/Steam/compatibilitytools.d/*/ "$HOME"/.local/share/Steam/steamapps/common/Proton*/; do
    [ -x "${d}files/bin/wine" ] && { echo "${d%/}"; return; }
  done
  return 1
}

detect() {
  COMPAT="$(find_compat)" || die "could not find compatdata/$APPID - launch Warframe once from Steam, or set WF_COMPAT"
  PROTON_DIR="$(find_proton)" || die "could not find a Proton build - set WF_PROTON"
  PFX="$COMPAT/pfx"
  WINE="$PROTON_DIR/files/bin/wine"
  WINESERVER="$PROTON_DIR/files/bin/wineserver"
  C="$PFX/drive_c"
  mkdir -p "$STATE_DIR/backup" "$CACHE_DIR"
  export WINEPREFIX="$PFX" WINEDEBUG=-all LD_PRELOAD=
  log "prefix : $PFX"
  log "proton : $PROTON_DIR"
}

# Registry edits are lost if a game session's wineserver is alive (it rewrites the hive on exit),
# so every script that touches the prefix must run with Warframe and Overwolf closed.
refuse_if_running() {
  if ps -eo cmd | grep -E "[W]arframe.x64.exe|[O]verwolf(Launcher|Browser)?.exe|compatdata/$APPID" | grep -v -E 'alecaframe-linux' >/dev/null; then
    die "Warframe/Overwolf appear to be running. Quit them completely and re-run."
  fi
}

w() { "$WINE" "$@" 2>&1 | grep -v -E 'MANGO|radv|ntsync|ProtonFixes|fsr4' || true; }
wait_wine() { "$WINESERVER" -w >/dev/null 2>&1 || true; }

fetch() { # fetch URL SHA256|- OUTFILE
  local url="$1" sha="$2" out="$3"
  if [ -f "$out" ] && { [ "$sha" = "-" ] || echo "$sha  $out" | sha256sum -c --status; }; then return; fi
  log "downloading $(basename "$out")"
  curl -fL --retry 3 -o "$out.part" "$url"
  mv "$out.part" "$out"
  if [ "$sha" != "-" ]; then echo "$sha  $out" | sha256sum -c --status || die "checksum mismatch for $out"; fi
}

overwolf_dir() { # prints the newest installed Overwolf version directory
  local base="$C/Program Files (x86)/Overwolf" v
  [ -d "$base" ] || return 1
  v="$(ls -1 "$base" | grep -E '^[0-9]+(\.[0-9]+)+$' | sort -V | tail -n1)" || return 1
  [ -n "$v" ] && echo "$base/$v"
}

reg_add() { w reg add "$@" /f >/dev/null; }

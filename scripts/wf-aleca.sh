#!/usr/bin/env bash
# Steam launch option for Warframe:
#     protonhax init <install-dir>/wf-aleca.sh %command%
# Steam runs this wrapper *outside* Steam's pressure-vessel container; only the final
# `proton waitforexitandrun <exe> <args>` enters it. Overwolf must run INSIDE the game's container (same user
# namespace as the game's wineserver) or Wine denies it access to other processes (EnumProcessModules ->
# ACCESS_DENIED, which crashes Overwolf at startup). So we rewrite that last command to run a small batch file
# that starts Overwolf/AlecaFrame and then the real Warframe launcher, all inside the container.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HERE/wf-aleca.log"

# unix path -> windows path, using the prefix's drive mappings (falls back to Z:)
to_win() {
  local p="$1" pfx="${STEAM_COMPAT_DATA_PATH:-}/pfx" best="" bestlen=0 l t letter
  if [ -d "$pfx/dosdevices" ]; then
    for l in "$pfx"/dosdevices/[a-y]:; do
      t="$(readlink -f "$l" 2>/dev/null)" || continue
      case "$p/" in "$t"/*) if [ "${#t}" -gt "$bestlen" ]; then best="$t"; bestlen=${#t}; letter="$(basename "$l")"; fi;; esac
    done
  fi
  if [ -n "$best" ]; then local rest="${p#"$best"}"; printf '%s%s' "${letter^^}" "${rest//\//\\}"
  else printf 'Z:%s' "${p//\//\\}"; fi
}

args=("$@"); out=(); n=${#args[@]}; i=0; done_rewrite=0
while (( i < n )); do
  out+=("${args[i]}")
  if (( ! done_rewrite )) && [[ "${args[i]}" == "waitforexitandrun" || "${args[i]}" == "run" ]] && (( i > 0 )) && [[ "${args[i-1]}" == */proton ]]; then
    if [ -f "$HERE/wf-launch.exe" ]; then   # GUI launcher: no console window to steal focus
      out+=("$(to_win "$HERE/wf-launch.exe")" "$(to_win "$HERE")" "$(to_win "${args[i+1]}")")
    else                                    # fallback: batch file via cmd.exe (opens a console window)
      out+=('C:\windows\system32\cmd.exe' '/c' "$(to_win "$HERE")\\wf-start.bat" "$(to_win "$HERE")" "$(to_win "${args[i+1]}")")
    fi
    ((i++)); done_rewrite=1
  fi
  ((i++))
done
{ echo "$(date) rewrite=$done_rewrite"; printf '  %s\n' "${out[@]}"; } >> "$LOG"
exec "${out[@]}"

#!/usr/bin/env bash
# Build wf-launch.exe (GUI-subsystem launcher, no console window). Usage: build-launcher.sh <out-dir>
set -euo pipefail
out="$1"; src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../src" && pwd)"
for c in clang ld.lld llvm-dlltool; do command -v "$c" >/dev/null || { echo "missing: $c" >&2; exit 1; }; done
mkdir -p "$out"; cd "$out"
printf 'LIBRARY kernel32.dll\nEXPORTS\nGetCommandLineW\nCreateProcessW\nWaitForSingleObject\nCloseHandle\nExitProcess\nGetFileAttributesW\nExpandEnvironmentStringsW\nGetEnvironmentVariableW\nSetEnvironmentVariableW\n' > k32.def
llvm-dlltool -m i386:x86-64 -d k32.def -l kernel32.lib
clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-stack-protector -mno-stack-arg-probe -nostdlib -fuse-ld=lld \
  -Wl,/subsystem:windows -Wl,/entry:start -Wl,/nodefaultlib -o wf-launch.exe "$src/wf-launch.c" kernel32.lib
echo "built $out/wf-launch.exe"

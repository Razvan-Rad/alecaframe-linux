#!/usr/bin/env bash
# Build the wintrust proxy (needs clang, lld, llvm-dlltool, llvm-readobj). Usage: build-wintrust.sh <proton-dir> <out-dir>
set -euo pipefail
proton="$1"; out="$2"; src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../src" && pwd)"
for c in clang ld.lld llvm-dlltool llvm-readobj; do command -v "$c" >/dev/null || { echo "missing: $c" >&2; exit 1; }; done
real="$proton/files/lib/wine/x86_64-windows/wintrust.dll"
[ -f "$real" ] || { echo "not found: $real" >&2; exit 1; }
mkdir -p "$out"; cd "$out"
# forward every export of Wine's wintrust (except WinVerifyTrust, which we implement) to wintrust_real.dll
{ echo 'LIBRARY wintrust'; echo 'EXPORTS'
  llvm-readobj --coff-exports "$real" | grep -E '^\s+Name:' | sed 's/ *Name: //' | grep -v -x WinVerifyTrust | sed 's/.*/&=wintrust_real.&/'
  echo 'WinVerifyTrust'; } > wintrust.def
{ printf 'LIBRARY kernel32.dll\nEXPORTS\n'; printf '%s\n' LoadLibraryA GetProcAddress GetModuleHandleW GetModuleFileNameW VirtualProtect \
  GetCurrentThread GetCurrentThreadId GetEnvironmentVariableA CreateFileW WriteFile CloseHandle; } > k32.def
llvm-dlltool -m i386:x86-64 -d k32.def -l kernel32.lib
clang --target=x86_64-pc-windows-msvc -O2 -ffreestanding -fno-stack-protector -nostdlib -fuse-ld=lld -shared \
  -Wl,/entry:DllMain -Wl,/nodefaultlib -Wl,/noimplib -Wl,/def:wintrust.def -o wintrust.dll "$src/wintrust.c" kernel32.lib
echo "built $out/wintrust.dll"

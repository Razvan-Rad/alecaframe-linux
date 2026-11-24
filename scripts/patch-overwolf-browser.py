#!/usr/bin/env python3
"""Give OverwolfBrowser.exe an entry point Wine's loader can run.

OverwolfBrowser.exe is a managed x64 exe that Overwolf post-processed with an extra native import
(owutils.dll!CreateHooker). It has AddressOfEntryPoint == 0 and is not flagged IL-only. Windows 8+ starts
such an image through mscoree!_CorExeMain; Wine only does that for IL-only images, so it jumps to the image
base and faults (STATUS_ACCESS_VIOLATION at 0x140000000) - taking down every Chromium helper process.

This adds an import of mscoree!_CorExeMain and a 6-byte `jmp [IAT]` stub in .text padding, and points the
entry point at it. The original is read from <backup>, so the patch is idempotent.

usage: patch-overwolf-browser.py <OverwolfBrowser.exe> <backup-of-original>
"""
import os, shutil, struct, sys

path, backup = sys.argv[1], sys.argv[2]
if not os.path.exists(backup):
    os.makedirs(os.path.dirname(backup), exist_ok=True)
    shutil.copy2(path, backup)

d = bytearray(open(backup, 'rb').read())
pe = struct.unpack_from('<I', d, 0x3c)[0]
nsec = struct.unpack_from('<H', d, pe + 6)[0]
opt = pe + 24
so = opt + struct.unpack_from('<H', d, pe + 20)[0]
dd = opt + 112                                    # data directories (PE32+)
sec = {}
for i in range(nsec):
    o = so + i * 40
    sec[struct.unpack_from('<8s', d, o)[0].rstrip(b'\0').decode()] = o
if '.text' not in sec or '.addImp' not in sec:
    sys.exit('unexpected layout (no .text/.addImp) - this Overwolf version may not need the patch')
T, A = sec['.text'], sec['.addImp']
if struct.unpack_from('<I', d, opt + 16)[0] != 0:
    sys.exit('entry point already set - nothing to do')

AV = struct.unpack_from('<I', d, A + 12)[0]       # .addImp virtual address
AR = struct.unpack_from('<I', d, A + 20)[0]       # .addImp raw offset
if struct.unpack_from('<I', d, A + 8)[0] != 0x64 or not all(b == 0 for b in d[AR + 0x64:AR + 0x200]):
    sys.exit('unexpected .addImp layout - refusing to patch')
desc0 = bytes(d[AR:AR + 20])                      # the existing owutils.dll import descriptor

def put(off, b):
    d[AR + off:AR + off + len(b)] = b

put(0x70, struct.pack('<QQ', AV + 0x90, 0))       # ILT  -> hint/name
put(0x80, struct.pack('<QQ', AV + 0x90, 0))       # IAT  -> hint/name (patched by the loader)
put(0x90, b'\0\0_CorExeMain\0')
put(0xa0, b'mscoree.dll\0')
put(0xc0, desc0 + struct.pack('<5I', AV + 0x70, 0, 0, AV + 0xa0, AV + 0x80) + b'\0' * 20)
struct.pack_into('<I', d, A + 8, 0x100)           # .addImp VirtualSize
struct.pack_into('<II', d, dd + 8, AV + 0xc0, 0x3c)   # import directory

tvs, tva, trp = (struct.unpack_from('<I', d, T + k)[0] for k in (8, 12, 20))
stub_va, stub_fo = tva + tvs, trp + tvs
if not all(b == 0 for b in d[stub_fo:stub_fo + 16]):
    sys.exit('no padding at end of .text - refusing to patch')
d[stub_fo:stub_fo + 6] = b'\xff\x25' + struct.pack('<i', AV + 0x80 - (stub_va + 6))   # jmp [rip+disp] -> IAT slot
struct.pack_into('<I', d, T + 8, tvs + 0x10)      # .text VirtualSize covers the stub
struct.pack_into('<I', d, opt + 16, stub_va)      # AddressOfEntryPoint

open(path, 'wb').write(d)
print(f'patched {path}: entry point -> {stub_va:#x}')

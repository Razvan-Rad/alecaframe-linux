# Troubleshooting: failure signatures → cause → fix

How each problem shows up in the logs, so you can tell which step you are stuck on. Log locations are inside the
prefix: `…/compatdata/230410/pfx/drive_c/users/steamuser/AppData/Local/Overwolf/Log/` (`Trace_*.log`,
`OverwolfCEF_*.log`, `Apps/<extension>/index.html.log`, `Warframe.x64_*.Game.html`) and
`…/AppData/Local/Warframe/EE.log`.

## Overwolf installer says WebView2 is missing / hangs

`InstallerTrace_*.log`: `WebView2 runtime not detected; cannot run web view installer`. The installer then idles.
→ install the WebView2 runtime into the prefix (`01-prefix-runtime.sh`).

## `winetricks dotnet48` fails

`err:msi:extract_cabinet FDICopy failed … netfx_core.mzz` / `netfx_full.mzz`, with the log showing
`CreateFileW Unable to create file …\Microsoft.NET\Framework64\v4.0.30319\diasymreader.dll (status c0000022)`.
Cause: Proton pre-populates `diasymreader.dll`, `fusion.dll`, `ngen.exe` there as symlinks into its read-only install;
the MSI cannot overwrite them. Fix: delete those six symlinks first.

Running the 4.8 installer directly then exits 0 without doing anything: its log says
`.NET Framework 4.8 or a later update is already installed on this computer` — it assumes 4.8 is built into Windows
10 build ≥ 19045. Fix: `winecfg -v win7` while installing, then back to `win10`.

## Overwolf: `mscoree.dll not found` / exit with no log

After 4.8 is installed the prefix has no `system32\mscoree.dll` (the 4.8 package does not ship it; on Windows it is
part of the OS). Take it from the .NET 4.0 installer (`netfx_Core.mzz`, `_003_mscoree_dll_*`) and set
`mscoree=native`.

## Overwolf: `COMException 0x80040152 (REGDB_E_KEYMISSING)` in `Launcher.Program..cctor`

`diasymreader.dll` exists but its COM class registration has no server. `regsvr32` both the 64- and 32-bit copies.

## Overwolf: `Win32Exception 0x80004005: Access denied` in `Process.MainModule`

`OverWolf.Client.Core.Managers.AppCenter.logStartupDetails` → `NtProcessManager.GetModuleInfos`. Reproducible in a
10-line C# program: `EnumProcessModules` on a real process handle returns `ERROR_ACCESS_DENIED`.
Cause: the game's wineserver runs inside Steam's pressure-vessel container (its own user namespace); processes you
start from outside it (`protonhax run`, plain `wine`) cannot be inspected by that server. Not fixed by
`kernel.yama.ptrace_scope=0`. Fix: run Overwolf inside the same container — launch wrapper (`03-install-launcher.sh`)
rewrites Steam's final `proton waitforexitandrun …` to run a batch file inside it.

## Overwolf starts but no window; every extension "crashed 5 times. Giving up."

`ExtensionWebApp - App crashed … (reason: ProcessCrashed exitcode: -1073741819 (STATUS_ACCESS_VIOLATION)`, and
`OverwolfCEF_*.log` full of `GPU process exited unexpectedly` / `Network service crashed`.
With `WINEDEBUG=+seh`: `Unhandled page fault on execute access to 0000000140000000` in `OverwolfBrowser.exe`.
Cause: `OverwolfBrowser.exe` is managed with `AddressOfEntryPoint = 0`, not IL-only, plus an appended `.addImp`
section importing `owutils.dll!CreateHooker`. Windows 8+ loaders start such images through `mscoree!_CorExeMain`;
Wine does so only for IL-only images. Fix: `patch-overwolf-browser.py` (adds a `_CorExeMain` import + jump stub).

## `Refusing to start - deployed assembly failed verification: …OverwolfBrowser.exe`

Overwolf checks Authenticode (`WinTrust.VerifyEmbeddedSignature` + certificate subject). The entry-point patch
breaks the signature digest. The `wintrust` proxy reports valid for that single filename (see README security notes).

## AlecaFrame shows "No game data"

Chain of evidence: AlecaFrame requests features `inventory`/`match_info` from Overwolf's Game Events Provider →
`Apps/Overwolf General GameEvents Provider/index.html.log` shows `game launched detected, 8954, waiting for renderer`
… `renderer poll - gave up` → `Warframe.x64_*.Game.html` shows the overlay hook firing (`fSwapChain_Present`,
`RenderDeviceD3d11::init`) then `initDX11 loading shaders… doOverlay Encountered Error … Unknown exception type
(0x80000100)` every frame. `0x80000100` is Wine's `EXCEPTION_WINE_STUB`; with `WINEDEBUG=+seh`:
`wine: Call from … to unimplemented function d3dx11_43.dll.D3DX11CompileFromResourceW, aborting`.
Fix: use Microsoft's real `d3dx11_43.dll` (Overwolf ships it) with override `native,builtin`.

Things that looked suspicious but were **not** the cause: `Bad data from inventory.php` lines in `EE.log` (the game
warning about unknown inventory fields); cross-process memory reads (verified working inside the container);
`ptrace_scope`.

## 3D camera / mouse capture lost after clicking the AlecaFrame window

Repro: click AlecaFrame's window, then click back on Warframe -> camera (relative-mouse look) is dead. Returning to
the game via **keyboard alt-tab**, or by clicking **a non-Wine window first** (e.g. a browser) and then the game,
restores it.

Cause: AlecaFrame (Overwolf) and Warframe run in the **same Wine prefix**, and Proton tags every window in the prefix
with the same WM_CLASS -- `steam_app_<SteamGameId>` (winex11 builds it from the `SteamGameId` env). So the window
manager sees AlecaFrame and Warframe as **one application**; a focus move between two windows of the same app does not
produce the clean cross-app focus-out/in that makes Wine re-grab the pointer for relative-mouse mode. A foreign
(non-Wine) window, or keyboard alt-tab, does produce it -- hence the workarounds.

Fix (in `src/wf-launch.c`, the launcher): start Overwolf with `SteamGameId=overwolf`, so its windows get a different
WM_CLASS (`steam_proton`) than the game's `steam_app_<appid>`. The WM then treats AlecaFrame as a separate app and
returning to the game re-grabs the pointer. The game's own `SteamGameId` is restored before the launcher runs, so the
game window keeps its normal class. Verified: overriding `SteamGameId` for a Wine process changes its WM_CLASS.
Does not affect Overwolf's overlay injection (it finds the game by process, not window class).

Things that did NOT fix it (for the record): `UseTakeFocus=N`, `GrabFullscreen=Y`, KWin window rules, KWin
focus-follows-mouse, borderless vs fullscreen, a Wine virtual desktop (and the virtual desktop / gamescope approaches
merge the two windows into one surface, which is usually not wanted). No game-side input config exists to change it
(Warframe uses ClipCursor + raw input with no exposed toggle).

## Overwolf keeps running after you quit Warframe

## Overwolf keeps running after you quit Warframe

Overwolf lives in the game's Wine session, so the session (and `protonhax`'s state, and Steam's "running" status)
stays alive until Overwolf exits. Registry edits made while it is alive are overwritten when its wineserver exits —
always quit Overwolf (`pkill -f OverwolfLauncher` and friends) before running the scripts.

## Ads

AlecaFrame pages load `https://content.overwolf.com/libs/ads/latest/owads.min.js` with `onload="MainWindowAds.ready()"`;
blocking that host means the ad code never starts. `scripts/adblock.sh`.

## Debugging recipes

- Wine trace for a launch: set `PROTON_LOG=1 WINEDEBUG=err+all,warn+module,+seh` in the wrapper script before
  `exec` (writes a large `~/steam-230410*.log`; remove afterwards).
- DXVK log: `DXVK_LOG_LEVEL=info DXVK_LOG_PATH=<dir>`.
- Compile and run small C# probes inside the prefix with `…/Microsoft.NET/Framework64/v4.0.30319/csc.exe` — handy for
  reproducing .NET behaviour (e.g. `Process.MainModule`) without the whole app.
- `ReflectionOnlyLoadFrom` + `MethodBody.GetILAsByteArray()` lets you list the calls a .NET method makes without a
  decompiler.

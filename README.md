# alecaframe-linux

Run [AlecaFrame](https://alecaframe.com) (via [Overwolf](https://www.overwolf.com)) alongside **Warframe on Linux**, under
Steam/Proton, with working in-game overlay and account sync.

The usual guide ("protonhax + install Overwolf + install AlecaFrame") stops working on newer setups. This repo
documents **why** (each failure has a log signature in [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)) and
automates the fixes.

> **Status:** worked end-to-end on CachyOS with `proton-cachyos-slr` 11.0 (Wine 11.0, 2026-10-15 build), Warframe
> (Steam app 230410), Overwolf 0.314.1.1, AlecaFrame 3.0.6, AMD GPU. The scripts were written from a manual
> session and **have not been run end-to-end from a clean prefix** — read them before running. Other Proton builds,
> Overwolf versions or distros may need adjustments. Not affiliated with Warframe/DE, Overwolf or AlecaFrame.

## What the fixes are

| # | Problem under Proton | Fix | Script |
|---|----------------------|-----|--------|
| 1 | Overwolf installer: *WebView2 runtime not detected* | install the WebView2 runtime in the prefix | `01-prefix-runtime.sh` |
| 2 | Overwolf crashes at startup (Wine Mono: `HttpClientHandler.set_Proxy` → `InvalidOperationException`) | install real **.NET Framework 4.8** (winetricks' `dotnet48` chain fails here; see below) | `01-prefix-runtime.sh` |
| 3 | Launcher crash `REGDB_E_KEYMISSING` | register `diasymreader.dll` | `01-prefix-runtime.sh` |
| 4 | Overwolf: `Win32Exception: Access denied` in `Process.MainModule` | run Overwolf **inside Steam's container** (launch wrapper) | `03-install-launcher.sh` |
| 5 | Every Chromium helper crashes (`STATUS_ACCESS_VIOLATION` at `0x140000000`) → no UI | entry-point patch for `OverwolfBrowser.exe` (+ signature-check proxy) | `02-overwolf-fixes.sh` |
| 6 | AlecaFrame says **"No game data"** | swap Wine's stub `d3dx11_43.dll` for Microsoft's real one | `02-overwolf-fixes.sh` |
| 7 | 3D camera stops capturing after clicking the AlecaFrame window, until you alt-tab or click via another app (KWin/XWayland) | launch Overwolf with a different `SteamGameId` so its windows get a distinct WM_CLASS and the WM treats AlecaFrame as a separate app | `wf-launch.exe` (launcher) |
| 8 | 3D camera dead after clicking back into Warframe (first click fails, clicking out twice "fixes" it) — Overwolf's in-game overlay code calls `AttachThreadInput`/`ShowCursor`/`SetForegroundWindow` on the game's input queue | "OW input guard" in the wintrust proxy rewrites those imports of `OWClient.dll` (inside `Warframe.x64.exe` only) to no-ops; overlay still renders. `OWGUARD=0` disables, log in `C:\users\steamuser\owguard.log` | `02-overwolf-fixes.sh` |
| – | (optional) ads | block the ad script's host | `adblock.sh` |

## Requirements

- Steam, and a Steam Linux Runtime ("SLR"/pressure-vessel) Proton build such as `proton-cachyos-slr` set as Warframe's compatibility tool. The scripts auto-detect the build and prefix (`WF_PROTON` / `WF_COMPAT` override).
  SLR (pressure-vessel) Proton. Use the same Proton build for Warframe that the scripts find (`WF_PROTON` to override).
- Launch Warframe **once** from Steam first so the prefix exists.
- [`protonhax`](https://github.com/jcnils/protonhax) (for `protonhax init` in the launch option).
- Tools: `curl`, `7z` (p7zip), `cabextract`, `python3`, and for the proxy build `clang`, `lld`, `llvm` (`llvm-dlltool`,
  `llvm-readobj`). On Arch/CachyOS: `sudo pacman -S curl p7zip cabextract python clang lld llvm protonhax`.
- Download from the vendors yourself (this repo ships **no** Microsoft/Overwolf/AlecaFrame binaries):
  `OverwolfSetup.exe` ([overwolf.com](https://www.overwolf.com/download)) and `AlecaFrame - Installer.exe`
  ([alecaframe.com](https://alecaframe.com)).

## Install

Quit Warframe and Overwolf completely before every step that edits the prefix (a running wineserver overwrites
registry edits when it exits).

```sh
git clone https://github.com/Razvan-Rad/alecaframe-linux && cd alecaframe-linux

# 1. WebView2 + .NET 4.8 + COM registration
scripts/01-prefix-runtime.sh

# 2. Install Overwolf into the *Warframe* prefix. Warframe must be running so protonhax can attach, and the
#    installer needs the WebView2 from step 1:
#       (launch Warframe from Steam first)   protonhax run 230410 'Z:\path\to\OverwolfSetup.exe'
#    then quit Warframe and Overwolf again.

# 3. Overwolf fixes (d3dx11_43, OverwolfBrowser.exe patch, wintrust proxy)
scripts/02-overwolf-fixes.sh

# 4. Launch wrapper; follow the printed instructions (Steam launch option + AlecaFrame installer location)
scripts/03-install-launcher.sh
```

First launch with the wrapper runs the AlecaFrame installer inside the game's session; click through it, then
restart Warframe. After that, Overwolf + AlecaFrame start automatically with the game. Toggle the overlay with
Overwolf's hotkey (default Ctrl+Shift+A for AlecaFrame).

**Account sync:** log in to Warframe as usual. AlecaFrame's status badge turns from "No game data" to OK once
Overwolf's Warframe events provider sees the game's renderer (step 6 above makes that work). If the data is
stale, enter and leave a relay once.

Optional ad block: `scripts/adblock.sh` (needs sudo; `scripts/adblock.sh remove` undoes it).

## Undo

`scripts/uninstall.sh` restores what `02-overwolf-fixes.sh` replaced (originals are backed up under
`~/.local/share/alecaframe-linux/backup`). Remove the Steam launch option to stop starting Overwolf. .NET 4.8 and
WebView2 are left in the prefix.

## Security notes — please read

- **`02-overwolf-fixes.sh` includes a `wintrust.dll` proxy** (`src/wintrust.c`). Overwolf's launcher verifies the
  Authenticode signature of its own files and refuses to start if `OverwolfBrowser.exe` is modified; the Wine
  patch for that file (fix 5) necessarily breaks its signature. The proxy reports "valid" **only** for a file named
  `OverwolfBrowser.exe` and forwards everything else to Wine's real `wintrust`. It is a compatibility workaround for
  your own install; it still weakens Overwolf's tamper check for that one filename inside this prefix. Skip step 3 if
  you are not comfortable with that — Overwolf will then not start.
- `scripts/03-install-launcher.sh` sets up a wrapper that rewrites Steam's launch command. Read `wf-aleca.sh`.
- The scripts download `.NET` installers from Microsoft and verify SHA-256 (hashes copied from winetricks).
- No Warframe account data is read or sent by these scripts. AlecaFrame/Overwolf behave exactly as they do on Windows.

## License

MIT — see `LICENSE`.

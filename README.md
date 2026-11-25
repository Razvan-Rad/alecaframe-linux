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
| 4 | Overwolf: `Win32Exception: Access denied` in `Process.MainModule` | run Overwolf **inside the game's Steam container** (launcher service + AlecaFrame shortcut) | `02-install-launcher.sh` |
| 5 | Every Chromium helper crashes (`STATUS_ACCESS_VIOLATION` at `0x140000000`) → no UI | entry-point patch for `OverwolfBrowser.exe` (+ signature-check proxy) | `03-overwolf-fixes.sh` |
| 6 | AlecaFrame says **"No game data"** | swap Wine's stub `d3dx11_43.dll` for Microsoft's real one | `03-overwolf-fixes.sh` |
| 7 | 3D camera stops capturing after clicking the AlecaFrame window, until you alt-tab or click via another app (KWin/XWayland) | start Overwolf with its own `SteamGameId`/`SteamAppId` so its windows get a distinct WM_CLASS and the WM treats AlecaFrame as a separate app | `alecaframe.sh` |
| 8 | 3D camera dead after clicking back into Warframe (first click fails, clicking out twice "fixes" it) — Overwolf's in-game overlay code calls `AttachThreadInput`/`ShowCursor`/`SetForegroundWindow` on the game's input queue | "OW input guard" in the wintrust proxy rewrites those imports of `OWClient.dll` (inside `Warframe.x64.exe` only) to no-ops; overlay still renders. `OWGUARD=0` disables, log in `C:\users\steamuser\owguard.log` | `03-overwolf-fixes.sh` |
| – | (optional) ads | block the ad script's host | `adblock.sh` |

## Requirements

- Steam, and a Steam Linux Runtime ("SLR"/pressure-vessel) Proton build such as `proton-cachyos-slr` set as
  Warframe's compatibility tool. The scripts auto-detect the build and prefix (`WF_PROTON` / `WF_COMPAT` override).
- Launch Warframe **once** from Steam first so the prefix exists.
- Tools: `curl`, `7z` (p7zip), `cabextract`, `python3`, and for the proxy build `clang`, `lld`, `llvm` (`llvm-dlltool`,
  `llvm-readobj`). On Arch/CachyOS: `sudo pacman -S curl p7zip cabextract python clang lld llvm`.
- Download from the vendors yourself (this repo ships **no** Microsoft/Overwolf/AlecaFrame binaries):
  `OverwolfSetup.exe` ([overwolf.com](https://www.overwolf.com/download)) and `AlecaFrame - Installer.exe`
  ([alecaframe.com](https://alecaframe.com)).

## How it runs

Warframe and AlecaFrame are two separate Steam entries that share one Wine session:

- **Warframe** keeps its normal Steam entry, with the launch option `…/wf-aleca.sh %command%`. The wrapper only
  asks Proton to start a steam-runtime *launcher service* inside the game's container.
- **AlecaFrame** is a non-Steam shortcut to `alecaframe.sh`. It waits for Warframe, joins the game's container
  through that service (`steam-runtime-launch-client --inside-app=230410`) and starts Overwolf + AlecaFrame there,
  with a separate window class so the window manager treats it as its own app. Stop in Steam closes Overwolf;
  Overwolf is also closed automatically when Warframe exits.

## Install

Quit Warframe and Overwolf completely before every step that edits the prefix (a running wineserver overwrites
registry edits when it exits).

```sh
git clone https://github.com/Razvan-Rad/alecaframe-linux && cd alecaframe-linux

# 1. WebView2 + .NET 4.8 + COM registration
scripts/01-prefix-runtime.sh

# 2. Warframe launch wrapper + AlecaFrame launcher. Follow the printed instructions: set Warframe's launch option,
#    add the "AlecaFrame" non-Steam shortcut, put 'AlecaFrame - Installer.exe' in ~/.local/share/alecaframe-linux
scripts/02-install-launcher.sh

# 3. Install Overwolf into the *Warframe* session: launch Warframe from Steam (with the new launch option), then
~/.local/share/alecaframe-linux/alecaframe.sh run ~/Downloads/OverwolfSetup.exe
#    click through the installer, then quit Overwolf and Warframe completely.

# 4. Overwolf fixes (d3dx11_43, OverwolfBrowser.exe patch, wintrust proxy + input guard)
scripts/03-overwolf-fixes.sh
```

Then: start **Warframe**, then **AlecaFrame** from Steam. The first AlecaFrame launch runs the AlecaFrame installer
inside the game's session; click through it, then restart both. After that AlecaFrame opens directly. Toggle the
overlay with Overwolf's hotkey (default Ctrl+Shift+A for AlecaFrame). Log: `~/.local/share/alecaframe-linux/alecaframe.log`.

**Account sync:** log in to Warframe as usual. AlecaFrame's status badge turns from "No game data" to OK once
Overwolf's Warframe events provider sees the game's renderer (fix 6 above makes that work). If the data is
stale, enter and leave a relay once.

Optional ad block: `scripts/adblock.sh` (needs sudo; `scripts/adblock.sh remove` undoes it).

## Undo

`scripts/uninstall.sh` restores what `03-overwolf-fixes.sh` replaced (originals are backed up under
`~/.local/share/alecaframe-linux/backup`) and removes the launcher files. Then clear Warframe's launch option and
remove the AlecaFrame shortcut in Steam. .NET 4.8, WebView2 and Overwolf are left in the prefix.

## Security notes — please read

- **`03-overwolf-fixes.sh` includes a `wintrust.dll` proxy** (`src/wintrust.c`). Overwolf's launcher verifies the
  Authenticode signature of its own files and refuses to start if `OverwolfBrowser.exe` is modified; the Wine
  patch for that file (fix 5) necessarily breaks its signature. The proxy reports "valid" **only** for a file named
  `OverwolfBrowser.exe` and forwards everything else to Wine's real `wintrust`. It is a compatibility workaround for
  your own install; it still weakens Overwolf's tamper check for that one filename inside this prefix. Skip step 4 if
  you are not comfortable with that — Overwolf will then not start.
- The same proxy contains the **Overwolf input guard** (fix 8). Inside `Warframe.x64.exe` only, it rewrites a few
  entries of the import table of Overwolf's injected `OWClient.dll`, so Overwolf's own calls to
  `AttachThreadInput`/`ShowCursor`/`SetForegroundWindow`/`LockSetForegroundWindow` do nothing and its raw-mouse
  registration is dropped. Warframe's own code and files are not touched. Set `OWGUARD=0` in Warframe's launch
  options (`OWGUARD=0 …/wf-aleca.sh %command%`) to turn it off.
- `wf-aleca.sh` only sets `STEAM_COMPAT_LAUNCHER_SERVICE=proton`; `alecaframe.sh` runs Overwolf through Steam's own
  `steam-runtime-launch-client`. Read both.
- The scripts download `.NET` installers from Microsoft and verify SHA-256 (hashes copied from winetricks).
- No Warframe account data is read or sent by these scripts. AlecaFrame/Overwolf behave exactly as they do on Windows.

## License

MIT — see `LICENSE`.

/* wf-launch.exe - tiny GUI-subsystem launcher (no console window).
 *
 *   wf-launch.exe <data-dir> <warframe-launcher.exe> [launcher args...]
 *
 * Replaces the `cmd /c wf-start.bat` step: that opened a visible cmd.exe console that grabbed focus right at the
 * Warframe launcher -> game hand-off. This starts Overwolf + AlecaFrame (or AlecaFrame's installer if its
 * extension isn't installed yet) and then runs the real Warframe launcher and waits for it, like `start /wait`.
 * Pass "-" as <data-dir> to skip the Overwolf/AlecaFrame part (used for testing).
 * Built freestanding with clang + lld (see scripts/build-launcher.sh).
 */
typedef unsigned short u16; typedef unsigned int u32; typedef unsigned long long u64; typedef unsigned char u8;
typedef void *HANDLE; typedef int BOOL;

typedef struct { u32 cb; u16 *lpReserved, *lpDesktop, *lpTitle; u32 x, y, xs, ys, xc, yc, fill, flags; u16 show, cbRes2; u8 *res2; HANDLE hin, hout, herr; } STARTUPINFOW;
typedef struct { HANDLE hProcess, hThread; u32 pid, tid; } PROCESS_INFORMATION;

__declspec(dllimport) u16 *__stdcall GetCommandLineW(void);
__declspec(dllimport) BOOL __stdcall CreateProcessW(const u16 *, u16 *, void *, void *, BOOL, u32, void *, const u16 *, STARTUPINFOW *, PROCESS_INFORMATION *);
__declspec(dllimport) u32 __stdcall WaitForSingleObject(HANDLE, u32);
__declspec(dllimport) BOOL __stdcall CloseHandle(HANDLE);
__declspec(dllimport) void __stdcall ExitProcess(u32);
__declspec(dllimport) u32 __stdcall GetFileAttributesW(const u16 *);
__declspec(dllimport) u32 __stdcall ExpandEnvironmentStringsW(const u16 *, u16 *, u32);
__declspec(dllimport) u32 __stdcall GetEnvironmentVariableW(const u16 *, u16 *, u32);
__declspec(dllimport) BOOL __stdcall SetEnvironmentVariableW(const u16 *, const u16 *);

#define BUF 2048
#define AF_ID "afmcagbpgggkpdkokjhjkllpegnadmkignlonpjm"   /* AlecaFrame's Overwolf extension id */
static u16 g_data[BUF], g_exe[BUF], g_cwd[BUF], g_cmd[BUF * 2], g_tmp[BUF], g_sgid[BUF];

static u64 wlen(const u16 *s) { u64 n = 0; while (s[n]) n++; return n; }
static void wcopy(u16 *d, const u16 *s) { while ((*d++ = *s++)) ; }
static void wcat(u16 *d, const u16 *s) { while (*d) d++; wcopy(d, s); }
static void wcatA(u16 *d, const char *s) { while (*d) d++; while ((*d++ = (u16)(u8)*s++)) ; }

/* read one (optionally quoted) token into out; return pointer just past it */
static u16 *token(u16 *p, u16 *out, u32 cap) {
  u32 n = 0;
  while (*p == ' ' || *p == '\t') p++;
  if (*p == '"') { p++; while (*p && *p != '"') { if (n + 1 < cap) out[n++] = *p; p++; } if (*p == '"') p++; }
  else { while (*p && *p != ' ' && *p != '\t') { if (n + 1 < cap) out[n++] = *p; p++; } }
  out[n] = 0;
  return p;
}

static BOOL run(const u16 *app, u16 *cmd, const u16 *cwd, BOOL wait) {
  STARTUPINFOW si; PROCESS_INFORMATION pi; u8 *z = (u8 *)&si; for (u64 i = 0; i < sizeof si; i++) z[i] = 0;
  si.cb = sizeof si;
  if (!CreateProcessW(app, cmd, 0, 0, 0, 0, 0, cwd, &si, &pi)) return 0;
  if (wait) WaitForSingleObject(pi.hProcess, 0xFFFFFFFFu);
  CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
  return 1;
}

void __stdcall start(void) {
  u16 *p = GetCommandLineW();
  p = token(p, g_tmp, BUF);                 /* program name */
  p = token(p, g_data, BUF);                /* data dir     */
  p = token(p, g_exe, BUF);                 /* launcher exe */
  while (*p == ' ' || *p == '\t') p++;      /* p = remaining args */
  if (!g_exe[0]) ExitProcess(2);

  if (!(g_data[0] == '-' && g_data[1] == 0)) {
    /* Give Overwolf's windows a DIFFERENT WM_CLASS than the game. Wine's winex11 builds the class as
     * "steam_app_<SteamGameId>"; the whole prefix shares SteamGameId=<appid>, so AlecaFrame and Warframe
     * look like one app to the window manager and focus moves between them never re-grab the pointer
     * (3D camera dies on click-return). Launching Overwolf with a different SteamGameId makes its windows
     * "steam_app_overwolf" -> the WM treats AlecaFrame as unrelated -> returning to the game is a real
     * cross-app activation that re-grabs. The game keeps its own SteamGameId (restored below). */
    g_sgid[0] = 0; GetEnvironmentVariableW(L"SteamGameId", g_sgid, BUF);   /* save original */
    SetEnvironmentVariableW(L"SteamGameId", L"overwolf");
    g_cwd[0] = 0; wcatA(g_cwd, "%LOCALAPPDATA%\\Overwolf\\Extensions\\" AF_ID);
    ExpandEnvironmentStringsW(g_cwd, g_tmp, BUF);
    if (GetFileAttributesW(g_tmp) != 0xFFFFFFFFu) {            /* AlecaFrame installed -> start it via Overwolf */
      g_cmd[0] = 0; wcatA(g_cmd, "\"C:\\Program Files (x86)\\Overwolf\\OverwolfLauncher.exe\" -launchapp " AF_ID " -ow-disable-gpu");
      run(L"C:\\Program Files (x86)\\Overwolf\\OverwolfLauncher.exe", g_cmd, 0, 0);
    } else {                                                    /* first run: installer from the data dir */
      wcopy(g_tmp, g_data); wcatA(g_tmp, "\\AlecaFrame - Installer.exe");
      if (GetFileAttributesW(g_tmp) != 0xFFFFFFFFu) { g_cmd[0] = '"'; g_cmd[1] = 0; wcat(g_cmd, g_tmp); wcatA(g_cmd, "\""); run(g_tmp, g_cmd, 0, 0); }
    }
    SetEnvironmentVariableW(L"SteamGameId", g_sgid);           /* restore for the game */
  }

  wcopy(g_cwd, g_exe);                                          /* cwd = launcher's folder */
  { u64 n = wlen(g_cwd); while (n && g_cwd[n - 1] != '\\' && g_cwd[n - 1] != '/') n--; if (n) g_cwd[n - 1] = 0; }
  g_cmd[0] = '"'; g_cmd[1] = 0; wcat(g_cmd, g_exe); wcatA(g_cmd, "\" "); wcat(g_cmd, p);
  ExitProcess(run(g_exe, g_cmd, g_cwd[0] ? g_cwd : 0, 1) ? 0 : 1);
}

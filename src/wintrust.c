/* wintrust.dll proxy for the Warframe Wine prefix.
 *
 * Overwolf's launcher refuses to start if OverwolfBrowser.exe fails an Authenticode check. That file has to be
 * patched for Wine (see scripts/patch-overwolf-browser.py), which invalidates its signature. This proxy reports
 * "valid" from WinVerifyTrust ONLY for a file literally named OverwolfBrowser.exe; every other call (and every
 * other export) is forwarded to Wine's real wintrust, renamed wintrust_real.dll. Overwolf's other integrity
 * checks are unaffected.
 *
 * Second job ("OW input guard", only inside Warframe.x64.exe): Overwolf injects OWClient.dll into the game for its
 * in-game overlay, and OWClient imports WINTRUST, so this proxy is loaded right next to it. From Overwolf's own
 * code (its own threads and its hooks running on the game's threads) OWClient calls ShowCursor, AttachThreadInput,
 * SetForegroundWindow and registers raw mouse input; under XWayland that leaves the game's 3D camera dead after you
 * click back into the window (first click fails, clicking out twice "fixes" it). We rewrite those entries in
 * OWClient's own import table only, so just Overwolf's calls are affected (no-ops; raw-input registration loses its
 * mouse entries); the game's own calls never go through OWClient's table. The overlay still renders.
 * Set OWGUARD=0 in the environment to disable. Decisions are logged to C:\users\steamuser\owguard.log.
 *
 * Built freestanding with clang + lld (no MinGW needed); see scripts/build-wintrust.sh.
 */
typedef unsigned short u16; typedef unsigned int u32; typedef unsigned long long u64; typedef unsigned char u8;
typedef void *HMODULE;
__declspec(dllimport) HMODULE __stdcall LoadLibraryA(const char *);
__declspec(dllimport) void *__stdcall GetProcAddress(HMODULE, const char *);
__declspec(dllimport) HMODULE __stdcall GetModuleHandleW(const u16 *);
__declspec(dllimport) u32 __stdcall GetModuleFileNameW(HMODULE, u16 *, u32);
__declspec(dllimport) int __stdcall VirtualProtect(void *, u64, u32, u32 *);
__declspec(dllimport) void *__stdcall GetCurrentThread(void);
__declspec(dllimport) u32 __stdcall GetCurrentThreadId(void);
__declspec(dllimport) u32 __stdcall GetEnvironmentVariableA(const char *, char *, u32);
__declspec(dllimport) void *__stdcall CreateFileW(const u16 *, u32, u32, void *, u32, u32, void *);
__declspec(dllimport) int __stdcall WriteFile(void *, const void *, u32, u32 *, void *);
__declspec(dllimport) int __stdcall CloseHandle(void *);

static const char suffix[] = "\\overwolfbrowser.exe";

static int ends_with_target(const u16 *p) {
  u64 n = 0; while (p[n] && n < 1024) n++;
  const u64 m = sizeof(suffix) - 1;
  if (n < m) return 0;
  for (u64 i = 0; i < m; i++) {
    u16 c = p[n - m + i]; if (c >= 'A' && c <= 'Z') c += 32;
    if (c != (u16)(u8)suffix[i]) return 0;
  }
  return 1;
}

typedef long (__stdcall *wvt_fn)(void *, void *, void *);
static wvt_fn real_wvt;

/* ---------------------------------------------------------------- OW input guard (Warframe.x64.exe only) */
static int g_state;                  /* 0 = not decided yet, 1 = active, -1 = not the game / disabled */
static u8 *g_ow, *g_ow_end;          /* OWClient.dll image range */
static long (__stdcall *g_ntqit)(void *, u32, void *, u32, u32 *);
static int (__stdcall *r_ShowCursor)(int);
static int (__stdcall *r_AttachThreadInput)(u32, u32, int);
static int (__stdcall *r_SetForegroundWindow)(void *);
static int (__stdcall *r_LockSetForegroundWindow)(u32);
static int g_loglines;

static void glog(const char *a, u64 v1, u64 v2) {     /* "<a> tid=<hex> v1=<hex> v2=<hex>\n", capped */
  if (g_loglines++ > 2000) return;
  char b[160]; u32 n = 0, w;
  for (const char *p = a; *p && n < 100; p++) b[n++] = *p;
  u64 vs[3] = { GetCurrentThreadId(), v1, v2 }; const char *lab[3] = { " tid=", " a=", " b=" };
  for (int k = 0; k < 3; k++) {
    for (const char *p = lab[k]; *p; p++) b[n++] = *p;
    for (int sh = 60; sh >= 0; sh -= 4) { u32 d = (vs[k] >> sh) & 15; if (d || sh == 0 || (n && b[n-1] != '=' && b[n-1] != 'x')) b[n++] = "0123456789abcdef"[d]; }
  }
  b[n++] = '\n';
  void *f = CreateFileW(L"C:\\users\\steamuser\\owguard.log", 4 /* FILE_APPEND_DATA */, 3, 0, 4 /* OPEN_ALWAYS */, 0x80, 0);
  if (f != (void *)-1) { WriteFile(f, b, n, &w, 0); CloseHandle(f); }
}

static u64 thread_start(void) { void *st = 0; if (g_ntqit) g_ntqit(GetCurrentThread(), 9 /* ThreadQuerySetWin32StartAddress */, &st, sizeof st, 0); return (u64)st; }

/* Everything below is reached only through OWClient's own import table, i.e. only from Overwolf code (running on
 * its own threads or inside its hooks on the game's threads). The game's own calls never pass through here. */
static int __stdcall g_ShowCursor(int show) {               /* overlay cursor: never touch the game's count */
  glog("block ShowCursor", (u64)show, thread_start()); return show ? 0 : -1;
}
static int __stdcall g_AttachThreadInput(u32 from, u32 to, int attach) {   /* merging input queues: never */
  glog("block AttachThreadInput", ((u64)from << 32) | to, (u64)attach); return 1;
}
static int __stdcall g_SetForegroundWindow(void *h) {
  glog("block SetForegroundWindow", (u64)h, thread_start()); return 1;
}
static int __stdcall g_LockSetForegroundWindow(u32 c) {
  glog("block LockSetForegroundWindow", c, thread_start()); return 1;
}
typedef struct { unsigned short page, usage; u32 flags; void *target; } RID;   /* RAWINPUTDEVICE (x64) */
static int (__stdcall *r_RegisterRawInputDevices)(const RID *, u32, u32);
static int __stdcall g_RegisterRawInputDevices(const RID *d, u32 n, u32 cb) {
  /* Raw input is one registration per usage per PROCESS: if Overwolf registers the mouse (page 1 / usage 2) for its
   * own window, the game's WM_INPUT mouse stream (= 3D camera) goes to Overwolf instead. Drop only mouse entries. */
  RID keep[16]; u32 k = 0;
  for (u32 i = 0; d && i < n; i++) {
    glog(d[i].page == 1 && d[i].usage == 2 ? "block RawInput mouse" : "pass RawInput",
         ((u64)d[i].page << 48) | ((u64)d[i].usage << 32) | d[i].flags, (u64)d[i].target);
    if (!(d[i].page == 1 && d[i].usage == 2) && k < 16) keep[k++] = d[i];
  }
  if (!k) return 1;
  return r_RegisterRawInputDevices(keep, k, cb);
}
static int lower_eq(const char *a, const char *b) {
  for (; *a && *b; a++, b++) { char x = *a, y = *b; if (x >= 'A' && x <= 'Z') x += 32; if (y >= 'A' && y <= 'Z') y += 32; if (x != y) return 0; }
  return *a == *b;
}
static int str_eq(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }

static void hook_iat(u8 *base, const char *name, void *repl, void **orig) {
  u8 *nt = base + *(u32 *)(base + 0x3c);
  u8 *opt = nt + 24;                                       /* PE32+ optional header */
  u32 imp_rva = *(u32 *)(opt + 112 + 8);                   /* DataDirectory[IMPORT].VirtualAddress */
  if (!imp_rva) return;
  for (u32 *d = (u32 *)(base + imp_rva); d[3]; d += 5) {   /* IMAGE_IMPORT_DESCRIPTOR: OFT, TDS, Fwd, Name, FT */
    if (!lower_eq((const char *)(base + d[3]), "user32.dll") || !d[0]) continue;
    u64 *oft = (u64 *)(base + d[0]), *iat = (u64 *)(base + d[4]);
    for (u32 i = 0; oft[i]; i++) {
      if (oft[i] >> 63) continue;                          /* by ordinal */
      if (!str_eq((const char *)(base + (u32)oft[i] + 2), name)) continue;
      if ((void *)iat[i] == repl) return;                  /* already hooked */
      u32 old; if (!VirtualProtect(&iat[i], 8, 4 /* PAGE_READWRITE */, &old)) return;
      *orig = (void *)iat[i]; iat[i] = (u64)repl;
      VirtualProtect(&iat[i], 8, old, &old);
      glog(name, (u64)*orig, (u64)repl);
      return;
    }
  }
}

static void guard_init(void) {
  if (g_state == 0) {
    u16 exe[1024]; u32 n = GetModuleFileNameW(0, exe, 1024);
    static const char t[] = "\\warframe.x64.exe"; const u32 m = sizeof t - 1; int ok = n >= m;
    for (u32 i = 0; ok && i < m; i++) { u16 c = exe[n - m + i]; if (c >= 'A' && c <= 'Z') c += 32; if (c != (u16)(u8)t[i]) ok = 0; }
    char e[4]; if (GetEnvironmentVariableA("OWGUARD", e, 4) && e[0] == '0') ok = 0;
    g_state = ok ? 1 : -1;
  }
  if (g_state != 1 || g_ow) return;
  u8 *ow = (u8 *)GetModuleHandleW(L"OWClient.dll");
  if (!ow) return;                                         /* not injected yet: retried from WinVerifyTrust */
  g_ntqit = (long (__stdcall *)(void *, u32, void *, u32, u32 *))GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtQueryInformationThread");
  g_ow_end = ow + *(u32 *)(ow + *(u32 *)(ow + 0x3c) + 24 + 56);   /* OptionalHeader.SizeOfImage */
  g_ow = ow;
  glog("guard: OWClient found", (u64)g_ow, (u64)g_ow_end);
  hook_iat(ow, "ShowCursor", (void *)g_ShowCursor, (void **)&r_ShowCursor);
  hook_iat(ow, "AttachThreadInput", (void *)g_AttachThreadInput, (void **)&r_AttachThreadInput);
  hook_iat(ow, "SetForegroundWindow", (void *)g_SetForegroundWindow, (void **)&r_SetForegroundWindow);
  hook_iat(ow, "LockSetForegroundWindow", (void *)g_LockSetForegroundWindow, (void **)&r_LockSetForegroundWindow);
  hook_iat(ow, "RegisterRawInputDevices", (void *)g_RegisterRawInputDevices, (void **)&r_RegisterRawInputDevices);
}

long __stdcall WinVerifyTrust(void *hwnd, void *action, void *data) {
  guard_init();
  /* WINTRUST_DATA (x64): dwUnionChoice @32, pFile @40; WINTRUST_FILE_INFO: pcwszFilePath @8 */
  if (data && *(u32 *)((u8 *)data + 32) == 1 /* WTD_CHOICE_FILE */) {
    u8 *pfile = *(u8 **)((u8 *)data + 40);
    if (pfile) {
      const u16 *path = *(const u16 **)(pfile + 8);
      if (path && ends_with_target(path)) return 0;
    }
  }
  if (!real_wvt) {
    HMODULE m = LoadLibraryA("wintrust_real.dll");
    if (m) real_wvt = (wvt_fn)GetProcAddress(m, "WinVerifyTrust");
  }
  return real_wvt ? real_wvt(hwnd, action, data) : (long)0x800B0100; /* TRUST_E_NOSIGNATURE */
}

int __stdcall DllMain(void *h, u32 r, void *x) { (void)h; (void)x; if (r == 1 /* PROCESS_ATTACH */) guard_init(); return 1; }

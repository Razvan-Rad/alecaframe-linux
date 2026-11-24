/* wintrust.dll proxy for the Warframe Wine prefix.
 *
 * Overwolf's launcher refuses to start if OverwolfBrowser.exe fails an Authenticode check. That file has to be
 * patched for Wine (see scripts/patch-overwolf-browser.py), which invalidates its signature. This proxy reports
 * "valid" from WinVerifyTrust ONLY for a file literally named OverwolfBrowser.exe; every other call (and every
 * other export) is forwarded to Wine's real wintrust, renamed wintrust_real.dll. Overwolf's other integrity
 * checks are unaffected.
 *
 * Built freestanding with clang + lld (no MinGW needed); see scripts/build-wintrust.sh.
 */
typedef unsigned short u16; typedef unsigned int u32; typedef unsigned long long u64; typedef unsigned char u8;
typedef void *HMODULE;
__declspec(dllimport) HMODULE __stdcall LoadLibraryA(const char *);
__declspec(dllimport) void *__stdcall GetProcAddress(HMODULE, const char *);

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

long __stdcall WinVerifyTrust(void *hwnd, void *action, void *data) {
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

int __stdcall DllMain(void *h, u32 r, void *x) { (void)h; (void)r; (void)x; return 1; }

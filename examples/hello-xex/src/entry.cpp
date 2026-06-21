// XEX entry-point wrapper; name matches /ENTRY: in add_xex.
#include <xtl.h>
extern "C" {
    BOOL WINAPI _CRT_INIT(HINSTANCE hDll, DWORD reason, LPVOID reserved);
    BOOL APIENTRY DllMain(HINSTANCE hDll, DWORD reason, LPVOID reserved);
}
extern "C" BOOL WINAPI GtampEntryPoint(HINSTANCE hDll, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        if (!_CRT_INIT(hDll, reason, reserved)) return FALSE;
        return DllMain((HMODULE)hDll, reason, reserved);
    }
    if (reason == DLL_PROCESS_DETACH) {
        BOOL dm = DllMain((HMODULE)hDll, reason, reserved);
        _CRT_INIT(hDll, reason, reserved);
        return dm;
    }
    _CRT_INIT(hDll, reason, reserved);
    return DllMain((HMODULE)hDll, reason, reserved);
}

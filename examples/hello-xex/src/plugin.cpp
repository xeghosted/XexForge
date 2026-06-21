#include <xtl.h>
// DLL plugin. OutputDebugStringA needs no xkelib.
static DWORD WINAPI Worker(LPVOID) {
    OutputDebugStringA("[hello-xex] hello from a Wine-built XEX-DLL\n");
    return 0;
}
BOOL APIENTRY DllMain(HMODULE, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        CreateThread(NULL, 0, Worker, NULL, 0, NULL);
    }
    return TRUE;
}

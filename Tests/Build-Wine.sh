#!/usr/bin/env bash
# End-to-end: build the hello-xex sample (DLL + EXE) under Wine and assert both
# XEX are produced and verified. Run under WSL with XEDK set.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
: "${XEDK:?set XEDK}"
command -v cmake >/dev/null || { echo "SKIP: cmake"; exit 0; }
command -v ntlm_auth >/dev/null || { echo "SKIP: ntlm_auth"; exit 0; }
ex="$DIR/examples/hello-xex"
rm -rf "$ex/build"
( cd "$ex" && cmake --preset xdk-wine > /tmp/hx-cfg.log 2>&1 \
   && cmake --build --preset xdk-wine > /tmp/hx-build.log 2>&1 ) \
   || { echo "FAIL: build"; cat /tmp/hx-cfg.log /tmp/hx-build.log; exit 1; }
rc=0
for t in hello_dll hello_exe; do
    f="$ex/build/$t.xex"
    if [ -f "$f" ] && [ "$(head -c4 "$f")" = "XEX2" ]; then echo "ok   - $t.xex"; else echo "FAIL - $t.xex"; rc=1; fi
done
[ $rc -eq 0 ] && echo "ok - hello-xex DLL+EXE built and verified under Wine"
exit $rc

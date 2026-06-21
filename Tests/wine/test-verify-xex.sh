#!/usr/bin/env bash
# Run under WSL: bash Tests/wine/test-verify-xex.sh   (needs cmake)
set -u
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
V="$DIR/cmake/verify-xex.cmake"; F="$DIR/Tests/wine/fixtures"
command -v cmake >/dev/null || { echo "SKIP: cmake"; exit 0; }
fail=0
expect() { # expect <desc> <want-rc 0|1> <args...>
    local desc="$1" want="$2"; shift 2
    if cmake "$@" -P "$V" >/dev/null 2>&1; then got=0; else got=1; fi
    if [ "$got" = "$want" ]; then echo "ok   - $desc"; else echo "FAIL - $desc (rc=$got want=$want)"; fail=1; fi
}
expect "good DLL passes"            0 -DXEX_TYPE=DLL -DDUMP_FROM="$F/good-dll.dump"
expect "DLL not-compressed fails"   1 -DXEX_TYPE=DLL -DDUMP_FROM="$F/bad-dll-notcompressed.dump"
expect "DLL double-wrap fails"      1 -DXEX_TYPE=DLL -DDUMP_FROM="$F/bad-dll-doublewrap.dump"
expect "good EXE passes"            0 -DXEX_TYPE=EXE -DDUMP_FROM="$F/good-exe.dump"
expect "EXE on DLL dump fails"      1 -DXEX_TYPE=EXE -DDUMP_FROM="$F/good-dll.dump"
exit $fail

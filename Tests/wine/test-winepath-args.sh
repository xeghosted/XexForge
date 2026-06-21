#!/usr/bin/env bash
# Unit tests for cmake/wine/winepath-args.sh. Stubs path translation (no Wine).
# Run under WSL: bash Tests/wine/test-winepath-args.sh
set -u
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
stub_winepath() { printf 'Z:'; printf '%s' "$1" | tr '/' '\\'; }
export WINEPATH_FN=stub_winepath
. "$DIR/cmake/wine/winepath-args.sh"

fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$2] got [$3]"; fail=1; fi; }

check "flag /nologo"        "/nologo"             "$(translate_one /nologo)"
check "flag /c"             "/c"                  "$(translate_one /c)"
check "flag /INCREMENTAL"   "/INCREMENTAL:NO"     "$(translate_one /INCREMENTAL:NO)"
check "/Fo object"          "/FoZ:\\b\\x.obj"     "$(translate_one /Fo/b/x.obj)"
check "/OUT output"         "/OUT:Z:\\b\\x.exe"   "$(translate_one /OUT:/b/x.exe)"
check "/LIBPATH"            "/LIBPATH:Z:\\xke"    "$(translate_one /LIBPATH:/xke)"
check "/I abs include"      "/IZ:\\a\\inc"        "$(translate_one /I/a/inc)"
check "/IMPLIB path"        "/IMPLIB:Z:\\b\\x.lib" "$(translate_one /IMPLIB:/b/x.lib)"
# XexForge imagexex flags:
check "/IN path"            "/IN:Z:\\b\\x.exe"    "$(translate_one /IN:/b/x.exe)"
check "/CONFIG path"        "/CONFIG:Z:\\a.xml"   "$(translate_one /CONFIG:/a.xml)"
check "bare src"            "Z:\\s\\a.cpp"        "$(translate_one s/a.cpp)"
check "bare lib name"       "xboxkrnl.lib"        "$(translate_one xboxkrnl.lib)"
exit $fail

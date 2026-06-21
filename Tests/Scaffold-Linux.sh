#!/usr/bin/env bash
# Scaffold a project on Linux via pwsh, then build + verify it under Wine.
# Run under WSL with XEDK set. SKIPs if pwsh/cmake/ntlm_auth are absent.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
: "${XEDK:?set XEDK}"
command -v pwsh      >/dev/null || { echo "SKIP: pwsh";      exit 0; }
command -v cmake     >/dev/null || { echo "SKIP: cmake";     exit 0; }
command -v ntlm_auth >/dev/null || { echo "SKIP: ntlm_auth"; exit 0; }

work="$(mktemp -d)"
pwsh -NoProfile -Command "Import-Module '$DIR/Wizard/XexScaffold.psm1' -Force; New-XexProject -Name 'HelloLin' -Type 'DLL' -TargetDir '$work' -ToolkitRoot '$DIR' -Generator 'Ninja' | Out-Null" \
    || { echo "FAIL: scaffold"; exit 1; }

proj="$work/HelloLin"
[ -f "$proj/CMakeLists.txt" ] && [ -f "$proj/cmake/wine/cl-wine" ] || { echo "FAIL: generated tree incomplete"; exit 1; }

( cd "$proj" && cmake --preset xdk-wine > "$work/cfg.log" 2>&1 \
   && cmake --build --preset xdk-wine > "$work/build.log" 2>&1 ) \
   || { echo "FAIL: build"; cat "$work/cfg.log" "$work/build.log"; exit 1; }

xex="$proj/build/HelloLin.xex"
[ -f "$xex" ] && [ "$(head -c4 "$xex")" = "XEX2" ] \
   && echo "ok - scaffolded-on-Linux project built + verified ($xex)" \
   || { echo "FAIL: no valid HelloLin.xex"; exit 1; }

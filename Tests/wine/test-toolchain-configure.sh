#!/usr/bin/env bash
# Configure a trivial probe with the toolchain under WSL; assert cl-wine resolved.
# Run under WSL with XEDK set.
set -u
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
: "${XEDK:?set XEDK}"
command -v cmake >/dev/null || { echo "SKIP: cmake"; exit 0; }
command -v ntlm_auth >/dev/null || { echo "SKIP: ntlm_auth"; exit 0; }
work="$(mktemp -d)"; cd "$work"
cat > CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.21)
project(probe CXX)
message(STATUS "COMPILER=${CMAKE_CXX_COMPILER}")
EOF
cmake -G Ninja -DCMAKE_TOOLCHAIN_FILE="$DIR/cmake/XdkXenon.toolchain.cmake" . > cfg.log 2>&1
if [ $? -eq 0 ] && grep -q "COMPILER=.*cl-wine" cfg.log; then
    echo "ok - toolchain resolves cl-wine on Linux"
else
    echo "FAIL"; cat cfg.log; exit 1
fi

# XexForge Linux/Wine Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make XexForge's CMake layer host-aware so the same project builds Xbox 360 `.xex` on Windows (direct XDK tools) and Linux/WSL (XDK tools under Wine), with automatic post-build XEX verification.

**Architecture:** Only the toolchain's program selection branches on host (`cl.exe` vs the `cl-wine` wrapper); the MSVC-syntax build rules in `XdkXex.cmake` stay unchanged because the wrappers translate Linux paths to Wine `Z:\` paths and accept the same arguments. A host-agnostic `verify-xex.cmake` (run via `cmake -P`) checks the result on both OS. Wrappers read `XEDK`/`WINEPREFIX` from the inherited build environment — no env-script.

**Tech Stack:** Bash (wrappers), CMake ≥ 3.21, Ninja, Wine 10 (wow64), the XDK `cl.exe`/`link.exe`/`lib.exe`/`imagexex.exe`, PowerShell (existing Windows tests).

## Global Constraints

- Unified env var **`XEDK`** = XDK root (a Windows path on Windows, a Linux/WSL path under Wine). Toolchain `FATAL_ERROR`s if unset on either host.
- Wine is wow64-only — never `WINEARCH=win32`. Wrappers default `WINEPREFIX=$HOME/.wine-xdk`, `WINEDEBUG=-all`, and strip `\r` from `winepath` output.
- **`ntlm_auth` (winbind) mandatory on Linux** — toolchain `FATAL_ERROR`s if absent (else `link.exe` dies with `LNK1101`).
- Existing add_xex flags stay: `/ALIGN:128,4096 /FIXED:NO /XEX:NO`, base libs `xboxkrnl xapilib`, compile defs `_XBOX NDEBUG _MSC_VER=1300`, compile flags `/MT /O1 /GL /EHs-c-`.
- DLL XEX → module flags `A` ("DLL module"), image base `0x90A00000` rebased from original `0x98000000`, COMPRESSED. EXE XEX → "title module".
- Wrappers read `XEDK`/`WINEPREFIX` from the inherited environment; nothing host-specific is injected into CMake rule strings.
- Everything Linux is tested under WSL. Commit identity repo-local `xeghosted`; NO AI-assistant/Co-Authored-By trailers; no "claude"/"anthropic" tokens in committed content.

---

### Task 1: Wine wrapper scripts (`cmake/wine/`)

The wrappers translate Linux paths to Wine `Z:\` paths and run the real XDK tool under `wine`. Adapted from the hardware-proven `xex-wine-build` wrappers: read `XEDK` (not `XEDK_UNIX`), no `INCLUDE`/`LIB` env (XexForge passes includes/libs via `-I`/`/LIBPATH`), and add the imagexex `/IN:`/`/CONFIG:` path-flags. Pure-logic translator is unit-tested with a stub (no Wine).

**Files:**
- Create: `cmake/wine/winepath-args.sh`, `cmake/wine/cl-wine`, `cmake/wine/link-wine`, `cmake/wine/lib-wine`, `cmake/wine/imagexex-wine`
- Test: `Tests/wine/test-winepath-args.sh`

**Interfaces:**
- Produces: `to_win_path <path>`, `translate_one <arg>`, `translate_args <args...>` (fills array `TRANSLATED_ARGS`, rewrites `@responsefile`). Wrappers `cl-wine`/`link-wine`/`lib-wine`/`imagexex-wine` exec `wine "$XEDK/bin/win32/<tool>.exe" "${TRANSLATED_ARGS[@]}"`.

- [ ] **Step 1: Write the failing test**

Create `Tests/wine/test-winepath-args.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -e bash -c 'bash /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/Tests/wine/test-winepath-args.sh'`
Expected: FAIL — `cmake/wine/winepath-args.sh` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `cmake/wine/winepath-args.sh`:

```bash
# winepath-args.sh — translate Linux paths in XDK-tool args to Wine drive paths.
# Sourced by the cl-wine / link-wine / lib-wine / imagexex-wine wrappers.
# Override the translator in tests with WINEPATH_FN=my_stub.

to_win_path() {
    if [ -n "${WINEPATH_FN:-}" ]; then "$WINEPATH_FN" "$1"; return; fi
    wine winepath -w "$1" 2>/dev/null | tr -d '\r'
}

translate_one() {
    local a="$1"
    case "$a" in
        /Fo*|/Fd*|/Fp*|/Fe*) printf '%s' "${a:0:3}"; to_win_path "${a:3}" ;;
        -I*)        printf -- '-I';        to_win_path "${a:2}" ;;
        /OUT:*)     printf '/OUT:';        to_win_path "${a#/OUT:}" ;;
        /IN:*)      printf '/IN:';         to_win_path "${a#/IN:}" ;;
        /CONFIG:*)  printf '/CONFIG:';     to_win_path "${a#/CONFIG:}" ;;
        /PDB:*)     printf '/PDB:';        to_win_path "${a#/PDB:}" ;;
        /IMPLIB:*)  printf '/IMPLIB:';     to_win_path "${a#/IMPLIB:}" ;;
        /LIBPATH:*) printf '/LIBPATH:';    to_win_path "${a#/LIBPATH:}" ;;
        # /I include path: anchor to /I/<abs> or /I.<rel> so link flags that
        # merely start with /I (/INCREMENTAL, /INCLUDE, /IGNORE) are NOT paths.
        /I/*|/I.*)  printf '/I';           to_win_path "${a:2}" ;;
        -*|/*)
            if [ -e "$a" ]; then to_win_path "$a"; else printf '%s' "$a"; fi ;;
        *)
            if [ -e "$a" ] || case "$a" in */*) true ;; *) false ;; esac; then
                to_win_path "$a"
            else
                printf '%s' "$a"
            fi ;;
    esac
}

translate_args() {
    TRANSLATED_ARGS=()
    local a tok rsp tmp
    for a in "$@"; do
        case "$a" in
            @*)
                rsp="${a#@}"; tmp="$(mktemp)"
                while IFS= read -r tok; do
                    [ -n "$tok" ] || continue
                    translate_one "$tok"; printf '\n'
                done < <(xargs -n1 printf '%s\n' < "$rsp") > "$tmp"
                TRANSLATED_ARGS+=( "@$(to_win_path "$tmp")" )
                ;;
            *)
                TRANSLATED_ARGS+=( "$(translate_one "$a")" )
                ;;
        esac
    done
}
```

Create `cmake/wine/cl-wine` (then `link-wine`, `lib-wine`, `imagexex-wine` are identical except the `.exe` and the debug label):

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/winepath-args.sh"
: "${XEDK:?cl-wine: set XEDK to the XDK root}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-xdk}"
export WINEDEBUG="${WINEDEBUG:--all}"
translate_args "$@"
[ -n "${XEXWINE_WRAP_DEBUG:-}" ] && printf 'cl-wine: %s\n' "${TRANSLATED_ARGS[*]}" >&2
exec wine "$XEDK/bin/win32/cl.exe" "${TRANSLATED_ARGS[@]}"
```

Create `cmake/wine/link-wine` (identical but for `link.exe`):
```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/winepath-args.sh"
: "${XEDK:?link-wine: set XEDK to the XDK root}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-xdk}"
export WINEDEBUG="${WINEDEBUG:--all}"
translate_args "$@"
[ -n "${XEXWINE_WRAP_DEBUG:-}" ] && printf 'link-wine: %s\n' "${TRANSLATED_ARGS[*]}" >&2
exec wine "$XEDK/bin/win32/link.exe" "${TRANSLATED_ARGS[@]}"
```

Create `cmake/wine/lib-wine` (identical but for `lib.exe`):
```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/winepath-args.sh"
: "${XEDK:?lib-wine: set XEDK to the XDK root}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-xdk}"
export WINEDEBUG="${WINEDEBUG:--all}"
translate_args "$@"
[ -n "${XEXWINE_WRAP_DEBUG:-}" ] && printf 'lib-wine: %s\n' "${TRANSLATED_ARGS[*]}" >&2
exec wine "$XEDK/bin/win32/lib.exe" "${TRANSLATED_ARGS[@]}"
```

Create `cmake/wine/imagexex-wine` (identical but for `imagexex.exe`):
```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/winepath-args.sh"
: "${XEDK:?imagexex-wine: set XEDK to the XDK root}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-xdk}"
export WINEDEBUG="${WINEDEBUG:--all}"
translate_args "$@"
[ -n "${XEXWINE_WRAP_DEBUG:-}" ] && printf 'imagexex-wine: %s\n' "${TRANSLATED_ARGS[*]}" >&2
exec wine "$XEDK/bin/win32/imagexex.exe" "${TRANSLATED_ARGS[@]}"
```

Make them executable:

```bash
chmod +x cmake/wine/cl-wine cmake/wine/link-wine cmake/wine/lib-wine cmake/wine/imagexex-wine
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -e bash -c 'bash /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/Tests/wine/test-winepath-args.sh'`
Expected: all `ok` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add cmake/wine Tests/wine/test-winepath-args.sh
git commit -m "Add Wine wrapper scripts for the XDK tools (Linux host)"
```

---

### Task 2: `cmake/verify-xex.cmake` — host-agnostic XEX verifier

Run via `cmake -P`; works on Windows (`imagexex.exe`) and Linux (`imagexex-wine`). Unit-tested with captured dump fixtures via `-DDUMP_FROM` (no Wine/imagexex needed).

**Files:**
- Create: `cmake/verify-xex.cmake`
- Create: `Tests/wine/fixtures/good-dll.dump`, `bad-dll-notcompressed.dump`, `bad-dll-doublewrap.dump`, `good-exe.dump`
- Test: `Tests/wine/test-verify-xex.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `cmake -DXEX=<f> -DXEX_TYPE=<DLL|EXE> -DXDK_IMAGEXEX=<tool> [-DDUMP_FROM=<file>] -P cmake/verify-xex.cmake` → exit 0 on pass, FATAL_ERROR (non-zero) naming the divergence on fail.

- [ ] **Step 1: Write the failing test**

Create the four fixtures.

`Tests/wine/fixtures/good-dll.dump`:
```
          A module flags
              DLL module
   90A00000 load address
   90A00000 image base address
   98000000 original base address
   90A02000 entry point
   COMPRESSED, ENCRYPTED
```
`Tests/wine/fixtures/bad-dll-notcompressed.dump`: same as good-dll but last line `   NOT-COMPRESSED, ENCRYPTED`.
`Tests/wine/fixtures/bad-dll-doublewrap.dump`: same as good-dll but `   98000000 image base address` (image base == original → not rebased).
`Tests/wine/fixtures/good-exe.dump`:
```
          1 module flags
              title module
   82000000 image base address
   82010498 entry point
   COMPRESSED, ENCRYPTED
```

Create `Tests/wine/test-verify-xex.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -e bash -c 'bash /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/Tests/wine/test-verify-xex.sh'`
Expected: FAIL — `cmake/verify-xex.cmake` does not exist (cmake errors, treated as non-zero; "good" cases report FAIL).

- [ ] **Step 3: Write minimal implementation**

Create `cmake/verify-xex.cmake`:

```cmake
# Verify an Xbox 360 XEX has the expected structure. Host-agnostic (run via cmake -P).
#   cmake -DXEX=<file> -DXEX_TYPE=<DLL|EXE> -DXDK_IMAGEXEX=<tool> [-DDUMP_FROM=<file>] -P verify-xex.cmake
if(NOT DEFINED XEX_TYPE)
    message(FATAL_ERROR "verify-xex: XEX_TYPE (DLL|EXE) is required")
endif()

if(DEFINED DUMP_FROM)
    file(READ "${DUMP_FROM}" _d)
else()
    if(NOT DEFINED XEX)
        message(FATAL_ERROR "verify-xex: XEX is required")
    endif()
    file(READ "${XEX}" _magic LIMIT 4 HEX)
    if(NOT _magic STREQUAL "58455832")
        message(FATAL_ERROR "verify-xex: ${XEX} is not a XEX2 (magic ${_magic})")
    endif()
    execute_process(COMMAND "${XDK_IMAGEXEX}" /DUMP "${XEX}"
        OUTPUT_VARIABLE _d ERROR_VARIABLE _e RESULT_VARIABLE _rc)
    if(NOT _rc EQUAL 0)
        message(FATAL_ERROR "verify-xex: imagexex /DUMP failed (${_rc}): ${_e}")
    endif()
endif()

if(XEX_TYPE STREQUAL "DLL")
    if(NOT _d MATCHES "DLL module")
        message(FATAL_ERROR "verify-xex: expected a DLL module")
    endif()
    string(REGEX MATCH "([0-9A-Fa-f]+) image base address" _ignore "${_d}")
    set(_ib "${CMAKE_MATCH_1}")
    string(REGEX MATCH "([0-9A-Fa-f]+) original base address" _ignore "${_d}")
    set(_ob "${CMAKE_MATCH_1}")
    if(_ib STREQUAL "" OR _ib STREQUAL "${_ob}")
        message(FATAL_ERROR "verify-xex: not rebased (image base '${_ib}' == original '${_ob}') — double-wrap?")
    endif()
    if(NOT _d MATCHES "(^|[^-])COMPRESSED")
        message(FATAL_ERROR "verify-xex: expected COMPRESSED")
    endif()
elseif(XEX_TYPE STREQUAL "EXE")
    if(NOT _d MATCHES "title module")
        message(FATAL_ERROR "verify-xex: expected a title module")
    endif()
else()
    message(FATAL_ERROR "verify-xex: unknown XEX_TYPE '${XEX_TYPE}'")
endif()
message(STATUS "verify-xex: OK (${XEX_TYPE})")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -e bash -c 'bash /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/Tests/wine/test-verify-xex.sh'`
Expected: all five `ok` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add cmake/verify-xex.cmake Tests/wine/fixtures Tests/wine/test-verify-xex.sh
git commit -m "Add host-agnostic verify-xex.cmake with fixture tests"
```

---

### Task 3: Host-aware toolchain (`cmake/XdkXenon.toolchain.cmake`)

Add the Windows/Linux branch + the unified `XEDK` env var + the Linux `ntlm_auth` check. Existing Windows behavior unchanged.

**Files:**
- Modify: `cmake/XdkXenon.toolchain.cmake`
- Test: `Tests/wine/test-toolchain-configure.sh`

**Interfaces:**
- Consumes: `cmake/wine/cl-wine` etc. (Task 1).
- Produces: a toolchain that resolves the compiler to `cl-wine` on Linux, `cl.exe` on Windows; exposes `XDK_IMAGEXEX`.

- [ ] **Step 1: Write the failing test**

Create `Tests/wine/test-toolchain-configure.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -e bash -c 'XEDK="/mnt/c/Program Files (x86)/Microsoft Xbox 360 SDK" bash /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/Tests/wine/test-toolchain-configure.sh'`
Expected: FAIL — the toolchain still hard-codes `cl.exe` (COMPILER does not contain `cl-wine`).

- [ ] **Step 3: Write the modified toolchain**

Replace the program-selection block in `cmake/XdkXenon.toolchain.cmake`. The file becomes:

```cmake
# Xbox 360 (Xenon / PowerPC, big-endian) — official XDK toolchain for CMake.
# Host-aware: Windows drives the XDK tools directly; Linux/WSL drives them under
# Wine via the cmake/wine/ wrappers (which translate Linux paths to Z:\ paths).
set(CMAKE_SYSTEM_NAME      Generic)
set(CMAKE_SYSTEM_PROCESSOR ppcbe)

if(NOT DEFINED ENV{XEDK})
    message(FATAL_ERROR "XEDK is not set. Set it to the XDK root (a Windows path on Windows, a Linux/WSL path under Wine).")
endif()

file(TO_CMAKE_PATH "$ENV{XEDK}" XDK_ROOT)
set(_xdk_bin "${XDK_ROOT}/bin/win32")

if(CMAKE_HOST_WIN32)
    set(CMAKE_C_COMPILER   "${_xdk_bin}/cl.exe")
    set(CMAKE_CXX_COMPILER "${_xdk_bin}/cl.exe")
    set(CMAKE_AR           "${_xdk_bin}/lib.exe")
    set(CMAKE_LINKER       "${_xdk_bin}/link.exe")
    set(XDK_IMAGEXEX       "${_xdk_bin}/imagexex.exe" CACHE FILEPATH "XEX packager")
else()
    # Linux/Wine: the wrappers translate Linux paths -> Wine Z:\ and run the
    # tool under wine. They read XEDK/WINEPREFIX from the build environment.
    set(_wine "${CMAKE_CURRENT_LIST_DIR}/wine")
    set(CMAKE_C_COMPILER   "${_wine}/cl-wine")
    set(CMAKE_CXX_COMPILER "${_wine}/cl-wine")
    set(CMAKE_AR           "${_wine}/lib-wine")
    set(CMAKE_LINKER       "${_wine}/link-wine")
    set(XDK_IMAGEXEX       "${_wine}/imagexex-wine" CACHE FILEPATH "XEX packager")
    find_program(NTLM_AUTH ntlm_auth)
    if(NOT NTLM_AUTH)
        message(FATAL_ERROR "ntlm_auth not found on PATH — install winbind, else the XDK link.exe fails with LNK1101 under Wine.")
    endif()
    unset(NTLM_AUTH CACHE)
endif()

# The 2010-era Xenon cl.exe confuses CMake's compiler identification/ABI probe.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_C_COMPILER_ID   MSVC)
set(CMAKE_CXX_COMPILER_ID MSVC)
set(CMAKE_C_COMPILER_FORCED   TRUE)
set(CMAKE_CXX_COMPILER_FORCED TRUE)

# XDK headers / import libs.
include_directories(SYSTEM "${XDK_ROOT}/include/xbox")
link_directories("${XDK_ROOT}/lib/xbox")

# Compile flags — matched to the proven xstd_test.vcxproj (C4005 on _MSC_VER expected).
add_compile_definitions(_XBOX NDEBUG _MSC_VER=1300)
add_compile_options(/MT /O1 /GL /EHs-c-)

set(CMAKE_FIND_ROOT_PATH "${XDK_ROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# NOTE: The Generic platform forces TARGET_SUPPORTS_SHARED_LIBS FALSE and GNU
# naming AFTER this toolchain runs. The MSVC conventions + build rules therefore
# live in cmake/XdkXex.cmake, include()d from the generated CMakeLists AFTER
# project(). See that file.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -e bash -c 'XEDK="/mnt/c/Program Files (x86)/Microsoft Xbox 360 SDK" bash /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/Tests/wine/test-toolchain-configure.sh'`
Expected: `ok - toolchain resolves cl-wine on Linux`.

- [ ] **Step 5: Commit**

```bash
git add cmake/XdkXenon.toolchain.cmake Tests/wine/test-toolchain-configure.sh
git commit -m "Make the XDK toolchain host-aware (Windows tools / Linux Wine wrappers)"
```

---

### Task 4: Wire verify into `add_xex` + declare XBOX subsystem for EXE (`cmake/XdkXex.cmake`)

Add the `verify-xex.cmake` POST_BUILD step and add `/SUBSYSTEM:XBOX` to the EXE branch (a title XEX should declare it; correct on both hosts). Rules unchanged otherwise (the wrappers make them host-transparent). This task's real end-to-end validation is Task 5.

**Files:**
- Modify: `cmake/XdkXex.cmake` (the EXE branch of `add_xex`, and the POST_BUILD `add_custom_command`)

**Interfaces:**
- Consumes: `cmake/verify-xex.cmake` (Task 2), `XDK_IMAGEXEX` (Task 3).
- Produces: `add_xex(...)` unchanged in signature; now verifies the produced `.xex`.

- [ ] **Step 1: Add the failing expectation (static)**

This is a CMake-rule change validated end-to-end in Task 5; here, add a guard the implementer checks by reading. After editing, `grep -q "verify-xex.cmake" cmake/XdkXex.cmake` and `grep -q "SUBSYSTEM:XBOX" cmake/XdkXex.cmake` must both succeed. Run before editing to confirm they fail:

Run: `wsl.exe -e bash -c 'cd /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template && grep -q verify-xex.cmake cmake/XdkXex.cmake && echo HAS || echo MISSING'`
Expected: `MISSING`.

- [ ] **Step 2: Edit the EXE branch**

In `cmake/XdkXex.cmake`, change the EXE branch of `add_xex` from:

```cmake
    elseif(XEX_TYPE STREQUAL "EXE")
        add_executable(${target} ${XEX_SOURCES})
```

to:

```cmake
    elseif(XEX_TYPE STREQUAL "EXE")
        add_executable(${target} ${XEX_SOURCES})
        # A title XEX must declare the XBOX subsystem (correct on both hosts).
        target_link_options(${target} PRIVATE "/SUBSYSTEM:XBOX")
```

- [ ] **Step 3: Add the verify POST_BUILD**

In `cmake/XdkXex.cmake`, change the trailing `add_custom_command` from:

```cmake
    set(_xex "${CMAKE_BINARY_DIR}/${target}.xex")
    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND "${XDK_IMAGEXEX}" /IN:$<TARGET_FILE:${target}> /OUT:${_xex} /CONFIG:${XEX_CONFIG}
        BYPRODUCTS "${_xex}"
        COMMENT "imagexex -> ${target}.xex"
        VERBATIM)
```

to:

```cmake
    set(_xex "${CMAKE_BINARY_DIR}/${target}.xex")
    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND "${XDK_IMAGEXEX}" /IN:$<TARGET_FILE:${target}> /OUT:${_xex} /CONFIG:${XEX_CONFIG}
        COMMAND "${CMAKE_COMMAND}" -DXEX=${_xex} -DXEX_TYPE=${XEX_TYPE}
                -DXDK_IMAGEXEX=${XDK_IMAGEXEX}
                -P "${CMAKE_CURRENT_LIST_DIR}/verify-xex.cmake"
        BYPRODUCTS "${_xex}"
        COMMENT "imagexex + verify -> ${target}.xex"
        VERBATIM)
```

- [ ] **Step 4: Verify the static guard passes**

Run: `wsl.exe -e bash -c 'cd /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template && grep -q verify-xex.cmake cmake/XdkXex.cmake && grep -q SUBSYSTEM:XBOX cmake/XdkXex.cmake && echo BOTH'`
Expected: `BOTH`. (Full behavior is exercised by Task 5's build.)

- [ ] **Step 5: Commit**

```bash
git add cmake/XdkXex.cmake
git commit -m "add_xex: verify the XEX post-build and declare XBOX subsystem for EXE"
```

---

### Task 5: Sample project + Linux end-to-end test (`examples/hello-xex/`, `Tests/Build-Wine.sh`)

The real validator for Tasks 1–4 on Wine. A multi-source DLL plugin + an EXE title, both via `add_xex`, referencing the repo's `cmake/` directly. Build under WSL with a Ninja-from-PATH preset and assert both `.xex` are produced and verified.

**Files:**
- Create: `examples/hello-xex/CMakeLists.txt`, `examples/hello-xex/CMakePresets.json`, `examples/hello-xex/Application_dll.xml`, `examples/hello-xex/Application_exe.xml`, `examples/hello-xex/src/entry.cpp`, `examples/hello-xex/src/plugin.cpp`, `examples/hello-xex/src/main.cpp`
- Test: `Tests/Build-Wine.sh`

**Interfaces:**
- Consumes: `add_xex` (Task 4), the host-aware toolchain (Task 3), wrappers (Task 1), verify (Task 2).
- Produces: `build/hello_dll.xex`, `build/hello_exe.xex`.

- [ ] **Step 1: Write the failing test**

Create `Tests/Build-Wine.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -e bash -c 'XEDK="/mnt/c/Program Files (x86)/Microsoft Xbox 360 SDK" bash /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/Tests/Build-Wine.sh'`
Expected: FAIL — `examples/hello-xex/` does not exist.

- [ ] **Step 3: Create the sample**

`examples/hello-xex/src/entry.cpp`:
```cpp
// XEX entry-point wrapper; name matches /ENTRY: in add_xex.
#include <xtl.h>
extern "C" {
    BOOL WINAPI _CRT_INIT(HINSTANCE hDll, DWORD reason, LPVOID reserved);
    BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID reserved);
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
```

`examples/hello-xex/src/plugin.cpp`:
```cpp
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
```

`examples/hello-xex/src/main.cpp`:
```cpp
#include <xtl.h>
int main() {
    OutputDebugStringA("[hello-xex] hello from a Wine-built XEX-EXE\n");
    return 0;
}
```

`examples/hello-xex/Application_dll.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<xex>
  <baseaddr addr="0x90A00000"/>
  <sysdll/>
  <format><compressed/></format>
  <mediatypes><default/><allpackages/></mediatypes>
  <gameregion><all/></gameregion>
</xex>
```

`examples/hello-xex/Application_exe.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<xex>
  <baseaddr addr="0x82000000"/>
  <format><compressed/></format>
  <mediatypes><default/><allpackages/></mediatypes>
  <gameregion><all/></gameregion>
</xex>
```

`examples/hello-xex/CMakeLists.txt`:
```cmake
cmake_minimum_required(VERSION 3.21)
project(hello_xex CXX)

# In-repo sample: reference the repo's real cmake/ (not a copy).
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/../../cmake")
include(XdkXex)

add_xex(hello_dll
    TYPE    DLL
    ENTRY   GtampEntryPoint
    CONFIG  "${CMAKE_SOURCE_DIR}/Application_dll.xml"
    SOURCES src/plugin.cpp src/entry.cpp)

add_xex(hello_exe
    TYPE    EXE
    CONFIG  "${CMAKE_SOURCE_DIR}/Application_exe.xml"
    SOURCES src/main.cpp)
```

`examples/hello-xex/CMakePresets.json`:
```json
{
  "version": 3,
  "cmakeMinimumRequired": { "major": 3, "minor": 21, "patch": 0 },
  "configurePresets": [
    {
      "name": "xdk-wine",
      "displayName": "Xbox 360 (XDK under Wine)",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build",
      "toolchainFile": "${sourceDir}/../../cmake/XdkXenon.toolchain.cmake"
    }
  ],
  "buildPresets": [ { "name": "xdk-wine", "configurePreset": "xdk-wine" } ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -e bash -c 'XEDK="/mnt/c/Program Files (x86)/Microsoft Xbox 360 SDK" bash /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/Tests/Build-Wine.sh'`
Expected: `ok - hello_dll.xex`, `ok - hello_exe.xex`, `ok - hello-xex DLL+EXE built and verified under Wine`.
If the build fails, set `XEXWINE_WRAP_DEBUG=1` in the env and re-run to see the translated wrapper command lines. If only the EXE fails and the cause is genuinely a pre-existing XexForge EXE-path gap unrelated to Wine, report DONE_WITH_CONCERNS with the log rather than reworking the Windows path.

- [ ] **Step 5: Commit**

```bash
git add examples/hello-xex Tests/Build-Wine.sh
git commit -m "Add hello-xex sample and Linux/Wine end-to-end build test"
```

---

### Task 6: Template preset, Windows test assertions, scaffolder coverage, README

Distribution + docs: make scaffolder-generated projects buildable on Linux (a `xdk-wine` template preset), assert the host-awareness statically on Windows, confirm the recursive copy carries the new files, and document the Linux flow.

**Files:**
- Modify: `template/CMakePresets.json.in`
- Modify: `Tests/Toolchain.Tests.ps1`
- Modify: `Tests/Scaffold.Tests.ps1`
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Add the failing Windows assertions**

Append to `Tests/Toolchain.Tests.ps1`:

```powershell
Test-Case 'toolchain is host-aware (Wine wrappers on non-Windows)' {
    $t = Get-Content -Raw $tc
    Assert-True ($t -match 'CMAKE_HOST_WIN32' -and $t -match 'cl-wine' -and $t -match 'ntlm_auth')
}
Test-Case 'verify-xex.cmake exists and add_xex invokes it' {
    Assert-True (Test-Path (Join-Path $root 'cmake\verify-xex.cmake'))
    $xex = Get-Content -Raw (Join-Path $root 'cmake\XdkXex.cmake')
    Assert-True ($xex -match 'verify-xex\.cmake')
}
```

Append to `Tests/Scaffold.Tests.ps1` (a generated project must carry the wrappers + verifier — the existing `Copy-Item -Recurse -Force` at `XexScaffold.psm1:136` already copies `cmake/` recursively, so this is a confirmation, not a scaffolder change). Use the file's existing helpers/signature (`New-TempDir`, `New-XexProject -Name -Type -TargetDir -ToolkitRoot -Generator`, `$r.ProjectDir`):

```powershell
Test-Case 'generated project carries the Wine wrappers and verifier' {
    $out = New-TempDir
    $r = New-XexProject -Name 'ScfWine' -Type 'DLL' -TargetDir $out -ToolkitRoot $root -Generator 'Ninja'
    Assert-True (Test-Path (Join-Path $r.ProjectDir 'cmake\wine\cl-wine'))
    Assert-True (Test-Path (Join-Path $r.ProjectDir 'cmake\verify-xex.cmake'))
    Remove-Item -Recurse -Force $out
}
```

- [ ] **Step 2: Run the Windows tests to verify the new cases fail**

Run (PowerShell): `pwsh -File Tests/Run-Tests.ps1`
Expected: the two new Toolchain cases fail (toolchain not yet host-aware / verify-xex absent — though if Tasks 2–4 are already merged they may pass; in that case this step confirms green). The Scaffold case passes only after Step 3 confirms the copy includes the new files.

- [ ] **Step 3: Add the `xdk-wine` template preset + README**

Replace `template/CMakePresets.json.in` with:

```json
{
  "version": 3,
  "cmakeMinimumRequired": { "major": 3, "minor": 21, "patch": 0 },
  "configurePresets": [
    {
      "name": "xdk",
      "displayName": "Xbox 360 (XDK, Windows)",
      "generator": "@GENERATOR@",
      "binaryDir": "${sourceDir}/build",
      "toolchainFile": "${sourceDir}/cmake/XdkXenon.toolchain.cmake"@MAKE_PROGRAM_BLOCK@
    },
    {
      "name": "xdk-wine",
      "displayName": "Xbox 360 (XDK under Wine, Linux)",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build",
      "toolchainFile": "${sourceDir}/cmake/XdkXenon.toolchain.cmake"
    }
  ],
  "buildPresets": [
    { "name": "xdk", "configurePreset": "xdk" },
    { "name": "xdk-wine", "configurePreset": "xdk-wine" }
  ]
}
```

Add a "Linux / Wine" section to `README.md` (place it after the existing Windows build instructions):

```markdown
## Linux / Wine

XexForge builds the same project on Linux (incl. WSL) using the XDK tools under
Wine — the `cmake/` layer is host-aware.

Prerequisites:
- Wine able to run the 32-bit XDK tools (modern wow64 Wine in its default prefix;
  do **not** set `WINEARCH=win32`).
- `ntlm_auth` — `sudo apt install winbind`. **Mandatory:** the XDK `link.exe`
  authenticates to `mspdbsrv` over NTLM; without it you get a misleading
  `LNK1101: incorrect MSPDB100.DLL version`.
- `cmake` and `ninja` (`sudo apt install cmake ninja-build`).
- A copy of the XDK; set `XEDK` to its path (e.g. on WSL,
  `export XEDK="/mnt/c/Program Files (x86)/Microsoft Xbox 360 SDK"`).

Build a generated project on Linux:

```sh
cmake --preset xdk-wine
cmake --build --preset xdk-wine     # -> build/<name>.xex (verified)
```

Set `XEXWINE_WRAP_DEBUG=1` to see the translated Wine command lines.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (Windows): `pwsh -File Tests/Run-Tests.ps1` — all green (host-aware + verify + scaffold-carries-wrappers).
Run (WSL, full Linux suite):
```
wsl.exe -e bash -c 'XEDK="/mnt/c/Program Files (x86)/Microsoft Xbox 360 SDK" bash -c "for t in Tests/wine/test-winepath-args.sh Tests/wine/test-verify-xex.sh Tests/wine/test-toolchain-configure.sh Tests/Build-Wine.sh; do bash /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/$t || exit 1; done"'
```
Expected: every suite's `ok` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add template/CMakePresets.json.in Tests/Toolchain.Tests.ps1 Tests/Scaffold.Tests.ps1 README.md
git commit -m "Add xdk-wine preset, host-awareness tests, and Linux/Wine docs"
```

---

## Notes for the implementer

- All Linux tests run under WSL with `XEDK="/mnt/c/Program Files (x86)/Microsoft Xbox 360 SDK"`; they `SKIP` cleanly if `cmake`/`ntlm_auth` are absent.
- The wrappers read `XEDK`/`WINEPREFIX` from the environment — there is no env-script, so nothing host-specific is baked into rule strings.
- The Windows path (existing PowerShell tests) must stay green: the toolchain change is additive (the `CMAKE_HOST_WIN32` branch preserves the old behavior).
- Do NOT push to any remote until the user asks.
- If the EXE target surfaces a pre-existing XexForge EXE-path issue under Wine that is NOT related to path translation or subsystem, flag it — do not silently rework the Windows behavior.

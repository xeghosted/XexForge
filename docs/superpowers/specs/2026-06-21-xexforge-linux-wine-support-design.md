# XexForge — Linux/Wine support for the CMake layer — design

Date: 2026-06-21
Repo: XexForge (local clone `xex-cmake-template`)

## Purpose

Make XexForge's CMake build layer **host-aware** so the *same* generated (or
hand-written) project builds Xbox 360 `.xex` on **both Windows (direct XDK
tools)** and **Linux/WSL (XDK tools under Wine)**, and add automatic post-build
XEX verification. This folds the hardware-proven `xex-wine-build` Wine pipeline
into XexForge.

## Scope

In scope (Approach A — in-file host branching, minimal new files):
- `cmake/XdkXenon.toolchain.cmake` becomes host-aware (Windows → `cl.exe`…;
  Linux → `cl-wine`… wrappers).
- Bundle the Wine wrappers under `cmake/wine/`.
- Add a host-agnostic `cmake/verify-xex.cmake` and wire it into `add_xex` as a
  POST_BUILD step (both module TYPEs, both OS).
- A second `xdk-wine` preset in the project template (Ninja from PATH).
- The scaffolder's `cmake/` copy step must include the new files (small change,
  NOT a cross-platform rewrite).
- A Linux end-to-end test + a sample project; a README "Linux/Wine" section.

Out of scope (deferred, noted):
- Making the PowerShell scaffolder (`New-XexProject`) run on Linux (PowerShell
  Core) — a follow-up sub-project. The WinForms wizard stays Windows-only.

## Constraints / learnings carried over (hardware-proven in `xex-wine-build`)

- Wine is wow64-only — never `WINEARCH=win32`; default prefix. `WINEPREFIX`
  default `$HOME/.wine-xdk`, `WINEDEBUG=-all`.
- **`ntlm_auth` (winbind) mandatory on Linux** — else `link.exe` dies with
  `LNK1101: incorrect MSPDB100.DLL version` (failed mspdbsrv NTLM RPC).
- `/XEX:NO /FIXED:NO` (already in XexForge's `add_xex`) — else imagexex
  double-wraps a non-loadable image.
- Compile defs include `_MSC_VER=1300` (expected C4005); flags `/MT /O1 /GL
  /EHs-c-` (existing XexForge set, unchanged).
- DLL plugin XEX → module flags `A` (DLL module / exports to title), base
  `0x90A00000` rebased from `0x98000000`, COMPRESSED. EXE title → title module,
  base `0x82000000`.
- Commit identity repo-local `xeghosted`; NO AI-assistant/Co-Authored-By
  trailers; no "claude"/"anthropic" tokens in committed content.

## Architecture (Approach A)

Only the **program selection** is host-specific. The MSVC-syntax build rule
strings in `cmake/XdkXex.cmake` (`<CMAKE_CXX_COMPILER> /nologo /c <SOURCE>
/Fo<OBJECT>`, etc.) stay **unchanged** — on Windows `<CMAKE_CXX_COMPILER>` is
`cl.exe`; on Linux it is `cl-wine`, which accepts the same MSVC arguments and
translates Linux paths to Wine `Z:\` paths internally before invoking the real
tool under `wine`. So only the toolchain file branches; the rules do not.

**Key simplification vs `xex-wine-build`:** no generated env-script. The
wrappers read `XEDK` / `WINEPREFIX` from the **inherited build environment**
(the user has `XEDK` exported; `cmake --build` passes the shell env down to
Ninja → the compile/link commands). Nothing host-specific is injected into rule
strings, so the "spaced path splits in Ninja" problem never arises. Includes and
libs flow through CMake's `include_directories`/`link_directories` → `-I` /
`/LIBPATH:` → translated by the wrappers; so the wrappers do NOT build
`INCLUDE`/`LIB` env (unlike `xex-wine-build`).

```
Linux build:
  *.cpp  --cl-wine (translate -I/Fo/paths, wine cl.exe)-->  *.obj
  *.obj  --link-wine (/dll /XEX:NO /ENTRY, wine link.exe)-->  *.dll/.exe (MZ)
  PE     --imagexex-wine (/IN /OUT /CONFIG, wine imagexex)-->  *.xex
  *.xex  --cmake -P verify-xex.cmake (imagexex /DUMP + assert per TYPE)-->  ok / fail
Windows build: identical rules, programs = cl.exe/link.exe/lib.exe/imagexex.exe
```

## Components

### 1. `cmake/XdkXenon.toolchain.cmake` (modified)

Unified env var **`XEDK`** (Windows path on Windows, Linux/WSL path on Linux).
`file(TO_CMAKE_PATH "$ENV{XEDK}" XDK_ROOT)`. Then:

```cmake
if(CMAKE_HOST_WIN32)
    set(CMAKE_C_COMPILER "${_xdk_bin}/cl.exe")  # + CXX, AR=lib.exe, LINKER=link.exe
    set(XDK_IMAGEXEX     "${_xdk_bin}/imagexex.exe" CACHE FILEPATH "...")
else()
    set(_wine "${CMAKE_CURRENT_LIST_DIR}/wine")
    set(CMAKE_C_COMPILER "${_wine}/cl-wine")     # + CXX, AR=lib-wine, LINKER=link-wine
    set(XDK_IMAGEXEX     "${_wine}/imagexex-wine" CACHE FILEPATH "...")
    find_program(NTLM_AUTH ntlm_auth)
    if(NOT NTLM_AUTH)
        message(FATAL_ERROR "ntlm_auth not found — install winbind (else link.exe LNK1101).")
    endif()
    unset(NTLM_AUTH CACHE)
endif()
```

Shared (unchanged): try-compile bypass, `CMAKE_*_COMPILER_ID MSVC`/`FORCED`,
`include_directories(SYSTEM "${XDK_ROOT}/include/xbox")`,
`link_directories("${XDK_ROOT}/lib/xbox")`, `add_compile_definitions(_XBOX
NDEBUG _MSC_VER=1300)`, `add_compile_options(/MT /O1 /GL /EHs-c-)`, find-root
settings.

### 2. `cmake/wine/` (new, Linux-only, bash) — from `xex-wine-build`, adapted

- `winepath-args.sh` — path/response-file translator. Add `/IN:` and `/CONFIG:`
  to the recognized path-flag set (XexForge's imagexex flags), in addition to
  the existing `/OUT:` etc. Keep the path-anchored `/I/*|/I.*` include rule.
- `cl-wine` — reads `XEDK`/`WINEPREFIX` from env, `translate_args`, `wine
  "$XEDK/bin/win32/cl.exe" …`. No `INCLUDE`/`LIB` env construction.
- `link-wine` — same, `link.exe`.
- `lib-wine` — NEW, same pattern, `lib.exe` (for static-library targets via
  `CMAKE_AR`).
- `imagexex-wine` — same, `imagexex.exe`.
All honor `XEXWINE_WRAP_DEBUG=1`; strip `\r` from `winepath`; propagate exit
codes.

### 3. `cmake/verify-xex.cmake` (new, host-agnostic, run via `cmake -P`)

Invoked `cmake -DXEX=<f> -DXEX_TYPE=<DLL|EXE> -DXDK_IMAGEXEX=<tool> -P …`.
Asserts: magic `XEX2` (`file(READ … LIMIT 4 HEX)` == `58455832`); runs
`${XDK_IMAGEXEX} /DUMP` and checks per TYPE:
- DLL → output contains `DLL module`, image base ≠ original base (rebased —
  catches double-wrap), and `COMPRESSED` (regex `(^|[^-])COMPRESSED` so
  `NOT-COMPRESSED` fails).
- EXE → output contains `title module`.
On mismatch `message(FATAL_ERROR …)` naming the property → non-zero → build
fails. Works on Windows (`imagexex.exe`) and Linux (`imagexex-wine`) — same dump
text.

### 4. `cmake/XdkXex.cmake` (minimal change)

`add_xex` unchanged in API and rules. Its existing imagexex POST_BUILD gains a
second `COMMAND` invoking `verify-xex.cmake` with `-DXEX/-DXEX_TYPE/-DXDK_IMAGEXEX`.

### 5. Template `template/CMakePresets.json.in` (add a preset)

Keep the Windows `xdk` preset (bundled Ninja). Add a static `xdk-wine`
configure+build preset: same `toolchainFile` and `binaryDir`, generator
`Ninja`, NO `CMAKE_MAKE_PROGRAM` (Ninja from PATH). Windows → `--preset xdk`,
Linux → `--preset xdk-wine`. Template text only; no new `@TOKEN@`.

### 6. Scaffolder `Wizard/XexScaffold.psm1` (small change)

Ensure the `cmake/` copy in `New-XexProject` copies recursively, including
`cmake/wine/*` and `cmake/verify-xex.cmake`, so generated projects can build on
Linux. No cross-platform/pwsh work — Windows-only scaffolder unchanged otherwise.

### 7. `examples/hello-xex/` (new) + `Tests/Build-Wine.sh` (new)

A minimal sample with one DLL plugin target and one EXE title target via
`add_xex`, used as the Linux e2e fixture and as documentation. Unlike a
scaffolder-generated project (which carries its own `cmake/` copy), this in-repo
sample references the repo's real `cmake/` directly (toolchain + module path via
a relative `../../cmake` path) so the test exercises the actual repo files, not
a copy. `Build-Wine.sh` (run in WSL): `cmake --preset xdk-wine && cmake --build`
→ passes only if both targets' `verify-xex` POST_BUILDs are green. The existing PowerShell tests cover
Windows; add assertions to `Tests/Toolchain.Tests.ps1` that the host branch +
wine programs are referenced and `verify-xex.cmake` exists.

### 8. README

Add a "Linux/Wine" section: prereqs (Wine wow64, `winbind`/`ntlm_auth`,
`cmake`+`ninja`), set `XEDK` to the Linux/WSL XDK path, `cmake --preset
xdk-wine && cmake --build`.

## Testing

- Windows: existing PowerShell harness + new static `Toolchain.Tests`
  assertions.
- Linux: `Tests/Build-Wine.sh` end-to-end on real Wine+XDK (DLL + EXE), verify
  POST_BUILDs must pass.

## Error handling

- Toolchain: missing `XEDK` (both OS) / `ntlm_auth` (Linux) → `FATAL_ERROR`.
- `verify-xex.cmake`: names the diverging property.
- Wrappers: propagate `wine` exit codes; `XEXWINE_WRAP_DEBUG=1` logs translated
  command lines.

## Footprint note

Generated projects carry their own `cmake/` copy, so the ~6 new files
(`cmake/wine/*` + `verify-xex.cmake`) travel into each. They are inert on
Windows (`wine/` never invoked; `verify-xex.cmake` runs cross-platform).

## Deferred

- `New-XexProject` under PowerShell Core on Linux (own follow-up spec).
- Wizard GUI stays Windows-only.

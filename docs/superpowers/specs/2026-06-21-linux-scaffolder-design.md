# XexForge — cross-platform scaffolder (pwsh on Linux) — design

Date: 2026-06-21
Repo: XexForge (local clone `xex-cmake-template`)

## Purpose

Make XexForge's project scaffolder (`Wizard/XexScaffold.psm1` / `New-XexProject`)
run under **PowerShell Core on Linux** as well as Windows, so projects can be
generated on Linux and built there with the existing `xdk-wine` preset. This
completes the Linux/Wine story (the build layer already works on Linux; only
project *generation* was Windows-only).

## Scope

In scope (Approach A1 — inline host guards in the one module):
- Make `Wizard/XexScaffold.psm1` host-neutral: forward-slash path literals, a
  5.1-safe `$script:OnWindows`, Windows-only detection guarded.
- Cross-platform test suite (`$onWin` skips for Windows-only cases) + a Linux
  scaffold→build→verify e2e.
- pwsh prerequisite documented + installed for testing.
- README "Generate a project on Linux" subsection.

Out of scope:
- The WinForms wizard (`Wizard/XexProjectWizard.ps1`) stays Windows-only (GUI).
- No second (bash/Python) scaffolder — one cross-platform module.

## Constraints / context

- `New-XexProject`'s public signature and the module's 10 exports are UNCHANGED.
- Must remain compatible with Windows PowerShell 5.1 (the wizard may launch
  under it): do NOT use a bare `$IsWindows` (undefined under 5.1 + StrictMode).
  Use `$script:OnWindows = ($PSVersionTable.Platform -ne 'Unix')` — under 5.1
  `Platform` is absent so the hashtable lookup yields `$null` (≠ 'Unix' →
  Windows); under pwsh 6+ it is `'Win32NT'`/`'Unix'`.
- Generated projects already build on Linux thanks to the prior feature: the
  toolchain's `file(CHMOD)` makes the copied `cmake/wine/*` wrappers executable
  and `.gitattributes eol=lf` keeps them LF. No extra exec/EOL logic is needed
  in the scaffolder.
- Linux scaffolding requires `pwsh` (`sudo apt install powershell`).
- Commit identity `xeghosted`; no AI-assistant/Co-Authored-By trailers; no
  "claude"/"anthropic" tokens.

## Architecture (A1)

Only the detection/path bits of the single module branch on host (inline
`$script:OnWindows` guards), mirroring the toolchain's in-file-branch approach.
`New-XexProject`, the template engine, and the exports are otherwise untouched.

```
pwsh (Linux): Import-Module Wizard/XexScaffold.psm1
              New-XexProject -Name X -Type DLL -TargetDir … -ToolkitRoot <repo> -Generator Ninja
                -> project with cmake/ (incl. wine/ + verify-xex), CMakePresets (xdk + xdk-wine), sources
cmake --preset xdk-wine && cmake --build   ->  X.xex (verify-xex gates the build)
```

## Component changes — `Wizard/XexScaffold.psm1`

### Module header
```powershell
Set-StrictMode -Version Latest
# 'Unix' on Linux/macOS; under WinPS 5.1 Platform is absent ($null) -> Windows.
$script:OnWindows = ($PSVersionTable.Platform -ne 'Unix')
```

### `Find-Xdk`
- Override and `$env:XEDK` checks use forward-slash literals
  (`'bin/win32/imagexex.exe'`).
- The hardcoded `C:/Program Files (x86)/Microsoft Xbox 360 SDK` default is
  consulted ONLY under `$script:OnWindows`. On Linux, return `$null` if `XEDK`
  is unset.

### `Test-XdkTools`
- `Join-Path $XdkRoot 'bin/win32'` (forward slash).

### `Find-BundledNinja`
- `if (-not $script:OnWindows) { return $null }` at the top — avoids the
  `${env:ProgramFiles(x86)}` null/`Join-Path` issues on Linux. Windows body
  unchanged.

### `Find-Generator` / `Get-MakeProgram`
- Unchanged. `Get-Command ninja` matches a PATH ninja first (Linux: returns
  `'Ninja'`); `Find-BundledNinja` now returns `$null` cleanly on Linux.

### `New-XexProject`
- `@MAKE_PROGRAM_BLOCK@` is filled ONLY under `$script:OnWindows` (the
  VS-bundled-ninja convenience is Windows-specific; on Linux the user builds via
  the token-free `xdk-wine` preset). On Linux `$mpBlock = ''`.
- The block uses `` `n `` (LF) instead of `` `r`n `` so generated JSON does not
  inject platform-foreign CRLF.
- `Copy-Item`/`Set-Content -Encoding UTF8` unchanged (pwsh 7 writes UTF-8 without
  BOM). Signature and token set unchanged.

## Tests

### Cross-platform suite
- `Run-Tests.ps1` runs under pwsh on both OS.
- Windows-only cases in `Tests/Detect.Tests.ps1` (VS-bundled-ninja / generator
  detection) are guarded by `$onWin = ($PSVersionTable.Platform -ne 'Unix')` and
  SKIP on Linux (visible skip line). Render/Scaffold/Toolchain/XexHelper tests
  are file/rendering based and run unchanged on both.
- The EXISTING `Tests/Scaffold.Tests.ps1` case "CMakePresets.json is valid JSON
  and embeds CMAKE_MAKE_PROGRAM when resolvable" must be made host-aware: its
  `CMAKE_MAKE_PROGRAM` embed assertion is Windows-only (on Linux
  `New-XexProject` intentionally emits an empty `MAKE_PROGRAM_BLOCK`, so the
  generated JSON has NO `CMAKE_MAKE_PROGRAM`). Guard the embed assertion with
  `$onWin`; on Linux instead assert the JSON does NOT contain
  `CMAKE_MAKE_PROGRAM` and that `configurePresets` contains an `xdk-wine`
  preset. The `Assert-Equal 'Ninja' configurePresets[0].generator` part stays on
  both OS (preset 0 is still `xdk` with `@GENERATOR@` → `Ninja`).

### Linux e2e
- `Tests/Scaffold-Linux.sh` (WSL): `command -v pwsh && command -v cmake &&
  ntlm_auth` gate (SKIP otherwise); `pwsh -c "Import-Module …; New-XexProject
  -Name HelloLin -Type DLL -TargetDir <tmp> -ToolkitRoot <repo> -Generator
  Ninja"`; then `cmake --preset xdk-wine && cmake --build` with `XEDK` set;
  assert `build/HelloLin.xex` exists and starts with `XEX2`. Proves
  generate→build→verify on Linux.

## pwsh prerequisite

Linux scaffolding needs PowerShell Core. Documented in the README; installed in
WSL (Microsoft apt repo, `powershell` package) for running the tests during
implementation. The Linux scaffold tests SKIP cleanly when `pwsh` is absent.

## Docs

README "Linux / Wine" section gains a "Generate a project on Linux" subsection:
install `pwsh`, `Import-Module Wizard/XexScaffold.psm1`, `New-XexProject -Name …
-Type DLL -TargetDir … -ToolkitRoot . -Generator Ninja`, then `cmake --preset
xdk-wine && cmake --build --preset xdk-wine`.

## Error handling

- `New-XexProject` needs no XDK to scaffold (the XDK is consumed at `cmake`
  build time), so it works on Linux without XDK detection.
- `Find-Xdk` / `Find-BundledNinja` return `$null` on Linux rather than throwing.
- The Linux e2e gates on `pwsh`/`cmake`/`ntlm_auth` and SKIPs when absent.

## Deferred

- The WinForms wizard under a Linux GUI — not pursued (Windows-only by nature).

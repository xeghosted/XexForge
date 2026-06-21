# XexForge Cross-Platform Scaffolder (pwsh on Linux) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make XexForge's scaffolder module (`Wizard/XexScaffold.psm1` / `New-XexProject`) run under PowerShell Core on Linux as well as Windows, so projects can be generated on Linux and built with the `xdk-wine` preset.

**Architecture:** Approach A1 — inline host guards in the single module (a 5.1-safe `$script:OnWindows`, forward-slash path literals, Windows-only detection guarded). The test suite is made cross-platform so `Run-Tests.ps1` runs under pwsh on both OS, plus a Linux scaffold→build→verify e2e. The WinForms wizard stays Windows-only.

**Tech Stack:** PowerShell (Windows PowerShell 5.1 + PowerShell Core 7 / `pwsh`), CMake, Ninja, Wine, the existing XexForge CMake layer.

## Global Constraints

- `New-XexProject`'s public signature and the module's 10 exports are UNCHANGED.
- Stay compatible with Windows PowerShell 5.1: do NOT use a bare `$IsWindows` (undefined under 5.1 + StrictMode). Use `$script:OnWindows = ($PSVersionTable.Platform -ne 'Unix')` (under 5.1 `Platform` is absent → `$null` ≠ 'Unix' → Windows; under pwsh 6+ it is 'Win32NT'/'Unix'). In test files (which can't see the module's `$script:` var) compute a local `$onWin = ($PSVersionTable.Platform -ne 'Unix')`.
- Do NOT use multi-argument `Join-Path` (pwsh 6+ only) — 5.1 takes two args. Use single forward-slash path strings (`'bin/win32/imagexex.exe'`), which resolve on both OS.
- On Linux: `XEDK` is a Linux path; generator is `Ninja` from PATH; `@MAKE_PROGRAM_BLOCK@` is left EMPTY (the Linux user builds via the token-free `xdk-wine` preset).
- Generated projects already build on Linux (toolchain `file(CHMOD)` + `.gitattributes eol=lf` from the prior feature) — no extra exec/EOL logic in the scaffolder.
- Linux scaffolding requires `pwsh` (`sudo apt install powershell`); Linux tests SKIP cleanly when `pwsh` is absent.
- Commit identity repo-local `xeghosted`; NO AI-assistant/Co-Authored-By trailers; no "claude"/"anthropic" tokens in committed content.

---

### Task 1: Host-aware scaffolder module (`Wizard/XexScaffold.psm1`)

Make the module run under pwsh on Linux. Validated here by the existing Windows pwsh suite (no regression); the Linux runtime proof comes in Tasks 2–3.

**Files:**
- Modify: `Wizard/XexScaffold.psm1`

**Interfaces:**
- Produces: same exports/signatures; new module-scoped `$script:OnWindows`. On Linux `New-XexProject` emits an empty `MAKE_PROGRAM_BLOCK`; `Find-BundledNinja` returns `$null`; `Find-Xdk` honors `$env:XEDK` (Linux path) and skips the Windows default.

- [ ] **Step 1: Run the existing Windows suite to capture the baseline (must stay green)**

Run (PowerShell): `pwsh -File Tests/Run-Tests.ps1`
Expected: `RESULT: 34 passed, 0 failed`.

- [ ] **Step 2: Add the host flag to the module header**

In `Wizard/XexScaffold.psm1`, immediately after `Set-StrictMode -Version Latest`, add:

```powershell
# 'Unix' on Linux/macOS; under Windows PowerShell 5.1 Platform is absent ($null
# -ne 'Unix' -> Windows). Avoids bare $IsWindows (undefined on 5.1 + StrictMode).
$script:OnWindows = ($PSVersionTable.Platform -ne 'Unix')
```

- [ ] **Step 3: Make `Find-Xdk` host-aware (forward slashes; Windows-only default)**

Replace the body of `Find-Xdk` with:

```powershell
function Find-Xdk {
    [CmdletBinding()] param([string]$Override)
    if ($Override) {
        if (Test-Path (Join-Path $Override 'bin/win32/imagexex.exe')) { return $Override }
        return $null
    }
    if ($env:XEDK) {
        if (Test-Path (Join-Path $env:XEDK 'bin/win32/imagexex.exe')) { return $env:XEDK }
    }
    if ($script:OnWindows) {
        $default = 'C:/Program Files (x86)/Microsoft Xbox 360 SDK'
        if (Test-Path (Join-Path $default 'bin/win32/imagexex.exe')) { return $default }
    }
    return $null
}
```

- [ ] **Step 4: Forward-slash `Test-XdkTools`**

In `Test-XdkTools`, change `$bin = Join-Path $XdkRoot 'bin\win32'` to:

```powershell
    $bin = Join-Path $XdkRoot 'bin/win32'
```
(and the three `Join-Path $bin 'cl.exe'`/`'link.exe'`/`'imagexex.exe'` lines are already separator-clean — leave them.)

- [ ] **Step 5: Guard `Find-BundledNinja` to Windows**

Add as the FIRST line inside `Find-BundledNinja`:

```powershell
    if (-not $script:OnWindows) { return $null }
```
Leave the rest of the function unchanged.

- [ ] **Step 6: Make `New-XexProject` emit `MAKE_PROGRAM_BLOCK` only on Windows**

In `New-XexProject`, replace the make-program block:

```powershell
    $makeProg = Get-MakeProgram -Generator $Generator
    $mpBlock = ''
    if ($makeProg) {
        $mp = ($makeProg -replace '\\','/')
        $mpBlock = ",`r`n      ""cacheVariables"": {`r`n        ""CMAKE_MAKE_PROGRAM"": ""$mp""`r`n      }"
    }
    $tokens['MAKE_PROGRAM_BLOCK'] = $mpBlock
```

with:

```powershell
    $mpBlock = ''
    if ($script:OnWindows) {
        $makeProg = Get-MakeProgram -Generator $Generator
        if ($makeProg) {
            $mp = ($makeProg -replace '\\','/')
            $mpBlock = ",`n      ""cacheVariables"": {`n        ""CMAKE_MAKE_PROGRAM"": ""$mp""`n      }"
        }
    }
    $tokens['MAKE_PROGRAM_BLOCK'] = $mpBlock
```

(Leave `Copy-Item`, the template map, and `Set-Content -Encoding UTF8` unchanged.)

- [ ] **Step 7: Run the Windows suite — no regression**

Run (PowerShell): `pwsh -File Tests/Run-Tests.ps1`
Expected: `RESULT: 34 passed, 0 failed` (the existing tests still pass on Windows; the make-program test still embeds `CMAKE_MAKE_PROGRAM` because `$script:OnWindows` is true).

- [ ] **Step 8: Commit**

```bash
git add Wizard/XexScaffold.psm1
git commit -m "Make XexScaffold module host-aware (runs under pwsh on Linux)"
```

---

### Task 2: Cross-platform test suite

Fix the test files so `Run-Tests.ps1` runs under pwsh on Linux as well as Windows (forward-slash paths, cross-platform temp dir, host-aware make-program assertion).

**Files:**
- Modify: `Tests/Detect.Tests.ps1`, `Tests/Render.Tests.ps1`, `Tests/XexHelper.Tests.ps1`, `Tests/Scaffold.Tests.ps1`, `Tests/Toolchain.Tests.ps1`

**Interfaces:**
- Consumes: the host-aware module (Task 1).
- Produces: a suite green under pwsh on both OS.

- [ ] **Step 1: Run the suite under pwsh on Linux to see it fail**

Run: `wsl.exe -e bash -c 'cd /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template && pwsh -File Tests/Run-Tests.ps1'`
Expected: FAIL — backslash path literals create wrong paths and `$env:TEMP` is null on Linux (errors / failed assertions).

- [ ] **Step 2: Fix import paths and temp dirs (forward slash + cross-platform temp)**

In `Tests/Detect.Tests.ps1`, `Tests/Render.Tests.ps1`, `Tests/Scaffold.Tests.ps1`, change the module import literal `'Wizard\XexScaffold.psm1'` to `'Wizard/XexScaffold.psm1'`.

In `Tests/Detect.Tests.ps1` lines 4 and 13, and `Tests/Scaffold.Tests.ps1` line 5, change `$env:TEMP` to `[System.IO.Path]::GetTempPath()`. Example (Detect.Tests.ps1):
```powershell
$fake = Join-Path ([System.IO.Path]::GetTempPath()) ("fakexdk_" + [guid]::NewGuid().ToString('N'))
```
and (Scaffold.Tests.ps1 `New-TempDir`):
```powershell
    $d = Join-Path ([System.IO.Path]::GetTempPath()) ("scaf_" + [guid]::NewGuid().ToString('N'))
```

- [ ] **Step 3: Forward-slash the remaining path literals**

Change these backslash path literals to forward slash (content/behaviour identical on both OS):
- `Tests/Detect.Tests.ps1:5` — `'bin\win32'` → `'bin/win32'`.
- `Tests/XexHelper.Tests.ps1:2` — `'cmake\XdkXex.cmake'` → `'cmake/XdkXex.cmake'`.
- `Tests/Scaffold.Tests.ps1` — `'src\entry.cpp'` (×2), `'cmake\XdkXex.cmake'`, `'cmake\wine\cl-wine'`, `'cmake\verify-xex.cmake'` → forward slash.
- `Tests/Toolchain.Tests.ps1` — `'cmake\XdkXenon.toolchain.cmake'` (line 2) and `'cmake\XdkXex.cmake'` (lines 20, 34) → forward slash. (The test NAME string on line 9, `'… uses bin\win32 tools'`, is display-only — leave it.)

- [ ] **Step 4: Make the make-program assertion host-aware**

In `Tests/Scaffold.Tests.ps1`, replace the existing case:

```powershell
Test-Case 'CMakePresets.json is valid JSON and embeds CMAKE_MAKE_PROGRAM when resolvable' {
    $out = New-TempDir
    $r = New-XexProject -Name 'PresetChk' -Type 'EXE' -TargetDir $out -ToolkitRoot $root -Generator 'Ninja'
    $json = Get-Content -Raw (Join-Path $r.ProjectDir 'CMakePresets.json')
    $obj = $json | ConvertFrom-Json
    Assert-Equal 'Ninja' $obj.configurePresets[0].generator
    if (Get-MakeProgram -Generator 'Ninja') { Assert-True ($json -match 'CMAKE_MAKE_PROGRAM') }
    Remove-Item -Recurse -Force $out
}
```

with:

```powershell
Test-Case 'CMakePresets.json valid JSON; make-program embed is host-aware' {
    $onWin = ($PSVersionTable.Platform -ne 'Unix')
    $out = New-TempDir
    $r = New-XexProject -Name 'PresetChk' -Type 'EXE' -TargetDir $out -ToolkitRoot $root -Generator 'Ninja'
    $json = Get-Content -Raw (Join-Path $r.ProjectDir 'CMakePresets.json')
    $obj = $json | ConvertFrom-Json
    Assert-Equal 'Ninja' $obj.configurePresets[0].generator
    Assert-True ([bool]($obj.configurePresets | Where-Object { $_.name -eq 'xdk-wine' }))
    if ($onWin) {
        if (Get-MakeProgram -Generator 'Ninja') { Assert-True ($json -match 'CMAKE_MAKE_PROGRAM') }
    } else {
        Assert-True (-not ($json -match 'CMAKE_MAKE_PROGRAM'))
    }
    Remove-Item -Recurse -Force $out
}
```

- [ ] **Step 5: Run the suite on BOTH OS**

Run (Linux): `wsl.exe -e bash -c 'cd /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template && pwsh -File Tests/Run-Tests.ps1'`
Expected: `RESULT: N passed, 0 failed`.
Run (Windows): `pwsh -File Tests/Run-Tests.ps1`
Expected: `RESULT: 34 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add Tests/Detect.Tests.ps1 Tests/Render.Tests.ps1 Tests/XexHelper.Tests.ps1 Tests/Scaffold.Tests.ps1 Tests/Toolchain.Tests.ps1
git commit -m "Make the PowerShell test suite cross-platform (runs under pwsh on Linux)"
```

---

### Task 3: Linux scaffold→build→verify end-to-end (`Tests/Scaffold-Linux.sh`)

Prove that a project scaffolded on Linux (via pwsh) builds and verifies under Wine.

**Files:**
- Create: `Tests/Scaffold-Linux.sh`

**Interfaces:**
- Consumes: the host-aware module (Task 1), the `xdk-wine` preset + toolchain + `add_xex` (prior feature).

- [ ] **Step 1: Write the failing test**

Create `Tests/Scaffold-Linux.sh`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `wsl.exe -e bash -c 'XEDK="/mnt/c/Program Files (x86)/Microsoft Xbox 360 SDK" bash /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/Tests/Scaffold-Linux.sh'`
Expected: FAIL — `Tests/Scaffold-Linux.sh` does not exist (before creation). After creating it, the first real run requires the module to be host-aware (Task 1) and pwsh installed.

- [ ] **Step 3: (implementation is the script itself — created in Step 1)**

No additional code. The deliverable is the script; its passing run is the proof.

- [ ] **Step 4: Run it to verify it passes**

Run: `wsl.exe -e bash -c 'XEDK="/mnt/c/Program Files (x86)/Microsoft Xbox 360 SDK" bash /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/Tests/Scaffold-Linux.sh'`
Expected: `ok - scaffolded-on-Linux project built + verified (.../HelloLin.xex)`.
(Requires `pwsh` installed in WSL: `sudo apt-get install -y powershell` via the Microsoft apt repo, or `XEXFORGE` maintainer's preferred method. If pwsh is missing the script SKIPs — install it to get a real pass.)

- [ ] **Step 5: Commit**

```bash
git add Tests/Scaffold-Linux.sh
git commit -m "Add Linux scaffold->build->verify end-to-end test"
```

---

### Task 4: README — "Generate a project on Linux"

Document the Linux scaffolding flow and the pwsh prerequisite.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Confirm the anchor exists**

Run: `wsl.exe -e bash -c 'grep -n "Linux / Wine" /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/README.md'`
Expected: a line number for the "## Linux / Wine" heading (added by the prior feature).

- [ ] **Step 2: Add the subsection**

In `README.md`, inside the "Linux / Wine" section (after the build instructions), add:

```markdown
### Generate a project on Linux

Project generation (`New-XexProject`) also runs on Linux under PowerShell Core.

```sh
sudo apt install powershell        # provides pwsh
pwsh -NoProfile -Command "Import-Module ./Wizard/XexScaffold.psm1; \
  New-XexProject -Name MyPlugin -Type DLL -TargetDir . -ToolkitRoot . -Generator Ninja"
cd MyPlugin
export XEDK=/path/to/your/'Microsoft Xbox 360 SDK'
cmake --preset xdk-wine
cmake --build --preset xdk-wine    # -> build/MyPlugin.xex (verified)
```

The generated project carries its own `cmake/` (toolchain + Wine wrappers +
`verify-xex`), so it builds the same way on Windows (`--preset xdk`) and Linux
(`--preset xdk-wine`). The WinForms wizard remains Windows-only.
```

- [ ] **Step 3: Verify no forbidden tokens**

Run: `wsl.exe -e bash -c 'grep -niE "claude|anthropic" /mnt/c/Users/BBC/Desktop/Projects/xex-cmake-template/README.md || echo CLEAN'`
Expected: `CLEAN`.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Document Linux project generation (pwsh + New-XexProject)"
```

---

## Notes for the implementer

- `pwsh` must be installed in WSL for the Task 2 Linux suite run and the Task 3 e2e. Install: add the Microsoft apt repo and `sudo apt-get install -y powershell` (or the maintainer's preferred method). The Task 3 script SKIPs cleanly without it.
- All Linux runs use `XEDK="/mnt/c/Program Files (x86)/Microsoft Xbox 360 SDK"`.
- Keep `Join-Path` two-argument and use forward-slash path strings (5.1 compatibility).
- Do NOT push to any remote until the user asks.

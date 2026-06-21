# XexForge

**Scaffold and build Xbox 360 `.xex` projects with CMake — on Windows or Linux/WSL (via Wine).**

XexForge generates self-contained Xbox 360 projects that compile with the official
XDK tools (`cl` → `link` → `imagexex`) through CMake, producing a proper rebased,
compressed `.xex` that loads on hardware. On Windows a small native wizard
(PowerShell + WinForms, no install) walks you through creating a project; on either
OS you can scaffold and build from the command line. The generated project is
self-contained and builds the same way on Windows (`--preset xdk`) and on Linux/WSL
under Wine (`--preset xdk-wine`).

![XexForge wizard](assets/wizard.png)

> The GUI wizard is Windows-only. The build and the `New-XexProject` scaffolder run
> on **both** Windows and Linux/WSL — the XDK tools are Windows binaries, but they
> run on Linux under Wine.

## Features

- **Both module types** — XEX-DLL plugins and XEX-EXE titles, via a single `add_xex()`.
- **Cross-platform builds** — the `cmake/` layer is host-aware: Windows drives the XDK
  tools directly; Linux/WSL drives them under Wine via bundled wrappers. The same
  generated project builds on both.
- **Automatic XEX verification** — every build runs `verify-xex` as a post-build step,
  catching the double-wrap / wrong-module-type mistakes that otherwise only surface as
  a crash on hardware.
- **GUI wizard (Windows)** — pick a name, XEX-DLL or XEX-EXE, target folder, optional
  xkelib. A prerequisite gate detects the XDK, CMake, and the **Visual Studio-bundled
  Ninja** (no `PATH` setup) before you proceed.
- **CLI scaffolder (Windows + Linux)** — `New-XexProject` runs under PowerShell Core on
  either OS (see [Generate a project on Linux](#generate-a-project-on-linux)).
- **Self-contained output** — each generated project carries its own `cmake/` core
  (toolchain + Wine wrappers + verifier) and a `CMakePresets.json`, so it builds from
  any terminal.
- **Optional xkelib** — wired by path only, never bundled.

## Requirements

**Windows:** the Xbox 360 XDK (the `XEDK` environment variable, or the default
`C:\Program Files (x86)\Microsoft Xbox 360 SDK`); **CMake ≥ 3.21** on `PATH`; and a
generator — **Ninja** (the wizard auto-detects the VS-bundled one) or **NMake** (run
from a VS/XDK developer prompt).

**Linux / WSL:** see [Linux / Wine](#linux--wine) below (Wine, `winbind`, CMake, Ninja,
a copy of the XDK, and — for scaffolding — PowerShell Core). There is no GUI wizard or
prerequisite gate on Linux; you install the prerequisites yourself and Ninja must be on
`PATH`.

## Quick start (Windows wizard)

1. Double-click `Wizard\Launch-Wizard.bat`.
2. Confirm the prerequisites are green.
3. Enter a name, pick **XEX-DLL** or **XEX-EXE**, choose a folder, optionally point at xkelib.
4. Click **Create**, then **Configure + Build**.

The `.xex` lands in `build\<ProjectName>.xex`.

## Building a generated project (no wizard)

```sh
cd MyProject
cmake --preset xdk           # Windows;   on Linux/WSL:  cmake --preset xdk-wine
cmake --build --preset xdk   #            on Linux/WSL:  cmake --build --preset xdk-wine
```

> **Portable builds (Windows):** generated projects embed the full Ninja path as
> `CMAKE_MAKE_PROGRAM` in the `xdk` preset, so this works from plain `cmd.exe` or a
> minimal PowerShell session — Ninja does not need to be on `PATH`. On Linux the
> `xdk-wine` preset uses Ninja from `PATH`.

## Linux / Wine

XexForge builds the same project on Linux (incl. WSL) using the XDK tools under Wine —
the `cmake/` layer is host-aware. Unlike Windows there is **no GUI wizard or
prerequisite gate**: install the prerequisites yourself, and Ninja must be on `PATH`.

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

### Generate a project on Linux

Project generation (`New-XexProject`) also runs on Linux under PowerShell Core.

Install PowerShell Core (`pwsh`) first — see Microsoft's [Installing PowerShell on Linux](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux) (it needs the Microsoft package repo; the exact steps vary by distro).

```sh
# (PowerShell Core / pwsh installed per the link above)
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

## What gets generated

A self-contained project (carries its own `cmake/` core):

```
MyProject/
  cmake/              XdkXenon.toolchain.cmake, XdkXex.cmake, verify-xex.cmake, wine/ (Linux wrappers)
  CMakeLists.txt
  CMakePresets.json   xdk (Windows) + xdk-wine (Linux) presets
  Application.xml     XEX image config (imagexex)
  src/                main.cpp (+ entry.cpp for XEX-DLL)
```

## How it works

| Piece | Role |
|-------|------|
| `cmake/XdkXenon.toolchain.cmake` | Host-aware: on Windows points CMake at the XDK `cl`/`link`/`lib` directly; on Linux at the `cmake/wine/` wrappers (which translate paths and run the tools under Wine). Sets the proven Xenon compile/link flags. |
| `cmake/XdkXex.cmake` (`add_xex()`) | Builds the PE (`/XEX:NO` + `/FIXED:NO` so imagexex can rebase it), links the base Xbox libs, packages the `.xex` via `imagexex`, and verifies it. |
| `cmake/verify-xex.cmake` | Post-build check (run via `cmake -P`, host-agnostic) asserting the `.xex` module type / rebase / compression per target type — fails the build on a bad image. |
| `cmake/wine/` | Bash wrappers (`cl-wine`/`link-wine`/`lib-wine`/`imagexex-wine`) that drive the XDK tools under Wine on Linux. |
| `Wizard/XexProjectWizard.ps1` | The WinForms wizard (Windows; a thin UI over `XexScaffold.psm1`). |
| `Wizard/XexScaffold.psm1` | Detection + template rendering + the `New-XexProject` scaffolder (runs under PowerShell Core on Windows and Linux). |

## xkelib

xkelib (community-reversed Xbox 360 kernel/xam extension headers) is an external
dependency and is **never bundled**. When enabled, the generated project adds its
folder to the include + library paths; xkelib's own `#pragma comment(lib, ...)` then
auto-link `kernelext`/`xamext`/`xav`.

## Repo layout (the toolkit itself)

```
Wizard/     the wizard + scaffolder module + launcher
cmake/      the toolchain + add_xex helper + verifier + Wine wrappers (copied into every generated project)
template/   the *.in project templates the scaffolder fills
examples/   a sample project used by the Linux end-to-end test
Tests/      PowerShell harness (cross-platform under pwsh) + Linux build/scaffold e2e scripts
```

## Tests

```sh
# PowerShell suite — runs under PowerShell Core on Windows or Linux:
pwsh -File Tests/Run-Tests.ps1

# Linux end-to-end (WSL, with XEDK set) — real Wine builds:
bash Tests/Build-Wine.sh        # builds the sample project + verifies the .xex
bash Tests/Scaffold-Linux.sh    # scaffolds via pwsh, then builds + verifies
```

## License

[MIT](LICENSE)

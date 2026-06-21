Set-StrictMode -Version Latest

function Find-Xdk {
    [CmdletBinding()] param([string]$Override)
    # If Override is provided, ONLY check that path (don't fall through to defaults)
    if ($Override) {
        if (Test-Path (Join-Path $Override 'bin\win32\imagexex.exe')) { return $Override }
        return $null
    }
    # Otherwise, check env var and default path
    if ($env:XEDK) {
        if (Test-Path (Join-Path $env:XEDK 'bin\win32\imagexex.exe')) { return $env:XEDK }
    }
    $default = 'C:\Program Files (x86)\Microsoft Xbox 360 SDK'
    if (Test-Path (Join-Path $default 'bin\win32\imagexex.exe')) { return $default }
    return $null
}

function Test-XdkTools {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$XdkRoot)
    $bin = Join-Path $XdkRoot 'bin\win32'
    [pscustomobject]@{
        Cl       = Test-Path (Join-Path $bin 'cl.exe')
        Link     = Test-Path (Join-Path $bin 'link.exe')
        Imagexex = Test-Path (Join-Path $bin 'imagexex.exe')
    }
}

function Find-BundledNinja {
    $candidates = [System.Collections.Generic.List[string]]::new()

    # Try vswhere first (fast, authoritative)
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $roots = & $vswhere -all -prerelease -property installationPath 2>$null
        if ($roots) { foreach ($r in $roots) { if ($r) { $candidates.Add($r.Trim()) } } }
    }

    # Fallback globs over both ProgramFiles roots
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $pf) { continue }
        $vsBase = Join-Path $pf 'Microsoft Visual Studio'
        if (Test-Path $vsBase) {
            Get-ChildItem $vsBase -Directory -Recurse -Depth 1 | ForEach-Object { $candidates.Add($_.FullName) }
        }
    }

    # Check exact known path inside each root
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $candidates) {
        if (-not $root -or -not $seen.Add($root)) { continue }
        $ninja = Join-Path $root 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'
        if (Test-Path $ninja) { return $ninja }
    }
    return $null
}

function Find-Generator {
    if (Get-Command ninja -ErrorAction SilentlyContinue) { return 'Ninja' }
    $bundled = Find-BundledNinja
    if ($bundled) {
        $ninjaDir = Split-Path $bundled -Parent
        if ($env:PATH -notlike "*$ninjaDir*") {
            $env:PATH = $ninjaDir + [System.IO.Path]::PathSeparator + $env:PATH
        }
        return 'Ninja'
    }
    if (Get-Command nmake -ErrorAction SilentlyContinue) { return 'NMake Makefiles' }
    return $null
}

function Get-MakeProgram {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Generator)
    if ($Generator -eq 'Ninja') {
        $c = Get-Command ninja -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
        return (Find-BundledNinja)
    }
    if ($Generator -like 'NMake*') {
        $c = Get-Command nmake -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    return $null
}

function Test-CMake {
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { return $null }
    return (& cmake --version | Select-Object -First 1)
}

function Expand-XexTemplate {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][hashtable]$Tokens
    )
    $out = $Text
    foreach ($k in $Tokens.Keys) { $out = $out.Replace("@$k@", [string]$Tokens[$k]) }
    return $out
}

function Get-UnresolvedTokens {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Text)
    $tokenMatches = [regex]::Matches($Text, '@[A-Z0-9_]+@')
    if ($tokenMatches.Count -eq 0) {
        return @()
    }
    [array]$values = $tokenMatches | ForEach-Object { $_.Value }
    [array]$result = $values | Sort-Object -Unique
    return @($result)
}

function Test-ProjectName {
    [CmdletBinding()] param([string]$Name)
    return [bool]($Name -match '^[A-Za-z][A-Za-z0-9_]*$')
}

function New-XexProject {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('DLL','EXE')][string]$Type,
        [Parameter(Mandatory)][string]$TargetDir,
        [Parameter(Mandatory)][string]$ToolkitRoot,
        [string]$EntrySymbol = 'GtampEntryPoint',
        [bool]$UseXkelib = $false,
        [string]$XkelibDir = '',
        [ValidateNotNullOrEmpty()][string]$Generator = 'Ninja',
        [switch]$Force
    )
    if (-not (Test-ProjectName $Name)) { throw "Invalid project name '$Name' (use a letter then letters/digits/_)." }

    $projDir = Join-Path $TargetDir $Name
    if ((Test-Path $projDir) -and -not $Force) { throw "Target already exists: $projDir (use -Force to overwrite)." }
    New-Item -ItemType Directory -Force -Path $projDir | Out-Null

    # Self-contained: copy the CMake core into the generated project.
    Copy-Item -Recurse -Force (Join-Path $ToolkitRoot 'cmake') (Join-Path $projDir 'cmake')

    $tokens = @{
        PROJECT_NAME  = $Name
        XEX_TYPE      = $Type
        ENTRY_SYMBOL  = $EntrySymbol
        ENTRY_SOURCES = if ($Type -eq 'DLL') { ' src/entry.cpp' } else { '' }
        USE_XKELIB    = if ($UseXkelib) { 'ON' } else { 'OFF' }
        XKELIB_DIR    = ($XkelibDir -replace '\\','/')
        GENERATOR     = $Generator
    }

    $makeProg = Get-MakeProgram -Generator $Generator
    $mpBlock = ''
    if ($makeProg) {
        $mp = ($makeProg -replace '\\','/')
        $mpBlock = ",`r`n      ""cacheVariables"": {`r`n        ""CMAKE_MAKE_PROGRAM"": ""$mp""`r`n      }"
    }
    $tokens['MAKE_PROGRAM_BLOCK'] = $mpBlock

    # template (.in) -> output relative path, per type
    $map = [ordered]@{
        'CMakeLists.txt.in'    = 'CMakeLists.txt'
        'CMakePresets.json.in' = 'CMakePresets.json'
    }
    if ($Type -eq 'DLL') {
        $map['Application_dll.xml.in'] = 'Application.xml'
        $map['src/main_dll.cpp.in']   = 'src/main.cpp'
        $map['src/entry.cpp.in']      = 'src/entry.cpp'
    } else {
        $map['Application_exe.xml.in'] = 'Application.xml'
        $map['src/main_exe.cpp.in']    = 'src/main.cpp'
    }

    $tmpl    = Join-Path $ToolkitRoot 'template'
    $created = New-Object System.Collections.Generic.List[string]
    foreach ($inRel in $map.Keys) {
        $src      = Join-Path $tmpl $inRel
        $text     = Get-Content -Raw -LiteralPath $src
        $rendered = Expand-XexTemplate -Text $text -Tokens $tokens
        $left     = @(Get-UnresolvedTokens -Text $rendered)
        if ($left.Count -gt 0) { throw "Unresolved tokens in $inRel : [$(@($left) -join ', ')]" }
        $dst = Join-Path $projDir $map[$inRel]
        New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
        Set-Content -LiteralPath $dst -Value $rendered -Encoding UTF8
        $created.Add($map[$inRel])
    }

    return [pscustomobject]@{ ProjectDir = $projDir; Files = $created.ToArray() }
}

Export-ModuleMember -Function Find-Xdk, Test-XdkTools, Find-Generator, Find-BundledNinja, `
    Get-MakeProgram, Test-CMake, Expand-XexTemplate, Get-UnresolvedTokens, Test-ProjectName, `
    New-XexProject

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'Wizard\XexScaffold.psm1') -Force

function New-TempDir {
    $d = Join-Path $env:TEMP ("scaf_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return $d
}

Test-Case 'scaffold DLL+xkelib renders with no leftover tokens' {
    $out = New-TempDir
    $r = New-XexProject -Name 'DemoPlugin' -Type 'DLL' -TargetDir $out -ToolkitRoot $root `
                        -UseXkelib $true -XkelibDir 'C:/xke' -Generator 'Ninja'
    $cml = Get-Content -Raw (Join-Path $r.ProjectDir 'CMakeLists.txt')
    Assert-True ((Get-UnresolvedTokens -Text $cml).Count -eq 0)
    Assert-True ($cml -match 'TYPE\s+DLL' -and $cml -match 'USE_XKELIB ON')
    Assert-True (Test-Path (Join-Path $r.ProjectDir 'src\entry.cpp'))
    Assert-True (Test-Path (Join-Path $r.ProjectDir 'cmake\XdkXex.cmake'))
    Assert-True (Test-Path (Join-Path $r.ProjectDir 'Application.xml'))
    Remove-Item -Recurse -Force $out
}
Test-Case 'scaffold EXE omits entry.cpp and uses EXE config' {
    $out = New-TempDir
    $r = New-XexProject -Name 'DemoTitle' -Type 'EXE' -TargetDir $out -ToolkitRoot $root -Generator 'Ninja'
    Assert-True (-not (Test-Path (Join-Path $r.ProjectDir 'src\entry.cpp')))
    $cml = Get-Content -Raw (Join-Path $r.ProjectDir 'CMakeLists.txt')
    Assert-True ((Get-UnresolvedTokens -Text $cml).Count -eq 0 -and $cml -match 'TYPE\s+EXE')
    $xml = Get-Content -Raw (Join-Path $r.ProjectDir 'Application.xml')
    Assert-True ($xml -match '0x82000000')
    Remove-Item -Recurse -Force $out
}
Test-Case 'scaffold rejects an invalid name' {
    $out = New-TempDir
    Assert-Throws { New-XexProject -Name '1bad' -Type 'EXE' -TargetDir $out -ToolkitRoot $root }
    Remove-Item -Recurse -Force $out
}
Test-Case 'scaffold refuses to overwrite without -Force' {
    $out = New-TempDir
    New-XexProject -Name 'Dup' -Type 'EXE' -TargetDir $out -ToolkitRoot $root | Out-Null
    Assert-Throws { New-XexProject -Name 'Dup' -Type 'EXE' -TargetDir $out -ToolkitRoot $root }
    Remove-Item -Recurse -Force $out
}
Test-Case 'CMakePresets.json is valid JSON and embeds CMAKE_MAKE_PROGRAM when resolvable' {
    $out = New-TempDir
    $r = New-XexProject -Name 'PresetChk' -Type 'EXE' -TargetDir $out -ToolkitRoot $root -Generator 'Ninja'
    $json = Get-Content -Raw (Join-Path $r.ProjectDir 'CMakePresets.json')
    $obj = $json | ConvertFrom-Json
    Assert-Equal 'Ninja' $obj.configurePresets[0].generator
    if (Get-MakeProgram -Generator 'Ninja') { Assert-True ($json -match 'CMAKE_MAKE_PROGRAM') }
    Remove-Item -Recurse -Force $out
}
Test-Case 'generated project carries the Wine wrappers and verifier' {
    $out = New-TempDir
    $r = New-XexProject -Name 'ScfWine' -Type 'DLL' -TargetDir $out -ToolkitRoot $root -Generator 'Ninja'
    Assert-True (Test-Path (Join-Path $r.ProjectDir 'cmake\wine\cl-wine'))
    Assert-True (Test-Path (Join-Path $r.ProjectDir 'cmake\verify-xex.cmake'))
    Remove-Item -Recurse -Force $out
}

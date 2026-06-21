$root = Split-Path -Parent $PSScriptRoot
$tc   = Join-Path $root 'cmake\XdkXenon.toolchain.cmake'

Test-Case 'toolchain file exists' { Assert-True (Test-Path $tc) }
Test-Case 'toolchain sets Generic system + ppc processor' {
    $t = Get-Content -Raw $tc
    Assert-True ($t -match 'CMAKE_SYSTEM_NAME\s+Generic' -and $t -match 'CMAKE_SYSTEM_PROCESSOR')
}
Test-Case 'toolchain exposes XDK_IMAGEXEX and uses bin\win32 tools' {
    $t = Get-Content -Raw $tc
    Assert-True ($t -match 'XDK_IMAGEXEX' -and $t -match 'bin/win32' -and $t -match 'cl\.exe')
}
Test-Case 'toolchain carries the proven compile flags' {
    $t = Get-Content -Raw $tc
    Assert-True ($t -match '_XBOX' -and $t -match 'NDEBUG' -and $t -match '_MSC_VER=1300' -and $t -match '/MT' -and $t -match '/O1' -and $t -match '/GL')
}
Test-Case 'shared-library (DLL) support lives in XdkXex (runs after project())' {
    # Generic forces TARGET_SUPPORTS_SHARED_LIBS FALSE *after* the toolchain runs,
    # so the MSVC conventions + link rules must live in XdkXex.cmake (post-project()).
    $xex = Get-Content -Raw (Join-Path $root 'cmake\XdkXex.cmake')
    Assert-True ($xex -match 'TARGET_SUPPORTS_SHARED_LIBS' -and $xex -match 'CMAKE_CXX_CREATE_SHARED_LIBRARY' -and $xex -match '\.dll')
}
Test-Case 'toolchain does NOT redundantly set clobbered shared-lib conventions' {
    # These must NOT be in the toolchain (Generic would clobber them); they belong in XdkXex.
    $t = Get-Content -Raw $tc
    Assert-True (-not ($t -match 'CMAKE_CXX_CREATE_SHARED_LIBRARY'))
}

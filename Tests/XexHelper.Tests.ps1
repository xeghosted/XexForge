$root = Split-Path -Parent $PSScriptRoot
$mod  = Join-Path $root 'cmake\XdkXex.cmake'

Test-Case 'XdkXex.cmake exists' { Assert-True (Test-Path $mod) }
Test-Case 'defines add_xex function' {
    Assert-True ((Get-Content -Raw $mod) -match 'function\(add_xex')
}
Test-Case 'handles DLL entry + dll link options' {
    $t = Get-Content -Raw $mod
    Assert-True ($t -match '/DLL' -and $t -match '/ENTRY:' -and $t -match '/ALIGN:128,4096')
}
Test-Case 'emits a plain PE + keeps relocations so imagexex produces a loadable XEX' {
    # /XEX:NO -> link emits a PE (not a XEX) for imagexex to convert; /FIXED:NO
    # keeps the .reloc table so imagexex rebases the image to its load address.
    # Without these the plugin crashes on load (double-wrapped / not rebased).
    $t = Get-Content -Raw $mod
    Assert-True ($t -match '/XEX:NO' -and $t -match '/FIXED:NO')
}
Test-Case 'runs imagexex as a post-build step' {
    $t = Get-Content -Raw $mod
    Assert-True ($t -match 'XDK_IMAGEXEX' -and $t -match 'POST_BUILD' -and $t -match '/CONFIG:')
}
Test-Case 'wires xkelib include + link dirs when enabled' {
    $t = Get-Content -Raw $mod
    Assert-True ($t -match 'USE_XKELIB' -and $t -match 'target_link_directories')
}
Test-Case 'links base Xbox import libraries' {
    # Names are passed bare (no .lib) so CMAKE_LINK_LIBRARY_SUFFIX appends .lib; the
    # XDK link.exe rejects GNU -l and double suffixes, so this is the working form.
    $t = Get-Content -Raw $mod
    Assert-True ($t -match 'xboxkrnl' -and $t -match 'xapilib' -and $t -match 'target_link_libraries')
}
Test-Case 'sets MSVC compile/link rules + library naming for the Generic platform' {
    $t = Get-Content -Raw $mod
    Assert-True ($t -match 'CMAKE_CXX_COMPILE_OBJECT' -and $t -match '/Fo' -and `
                $t -match 'CMAKE_CXX_CREATE_STATIC_LIBRARY' -and $t -match '/OUT:' -and `
                $t -match 'CMAKE_LIBRARY_PATH_FLAG' -and $t -match '/LIBPATH:')
}

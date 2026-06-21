Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Wizard\XexScaffold.psm1') -Force

# Build a fake XDK in a temp dir so Find-Xdk/Test-XdkTools are deterministic.
$fake = Join-Path $env:TEMP ("fakexdk_" + [guid]::NewGuid().ToString('N'))
$bin  = Join-Path $fake 'bin\win32'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
foreach ($t in 'cl.exe','link.exe','imagexex.exe') { Set-Content -Path (Join-Path $bin $t) -Value '' }

Test-Case 'Find-Xdk honours -Override when tools present' {
    Assert-Equal $fake (Find-Xdk -Override $fake)
}
Test-Case 'Find-Xdk returns null for a dir without imagexex' {
    $empty = Join-Path $env:TEMP ("empty_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $empty | Out-Null
    Assert-True ($null -eq (Find-Xdk -Override $empty))
}
Test-Case 'Test-XdkTools reports all three present' {
    $r = Test-XdkTools -XdkRoot $fake
    Assert-True ($r.Cl -and $r.Link -and $r.Imagexex)
}
Test-Case 'Find-Generator returns a known value or null' {
    $g = Find-Generator
    Assert-True ($g -in @('Ninja','NMake Makefiles',$null))
}

Remove-Item -Recurse -Force $fake -ErrorAction SilentlyContinue

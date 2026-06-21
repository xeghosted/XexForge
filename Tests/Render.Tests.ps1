Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Wizard\XexScaffold.psm1') -Force

Test-Case 'Expand-XexTemplate substitutes tokens' {
    $out = Expand-XexTemplate -Text 'name=@PROJECT_NAME@;type=@XEX_TYPE@' -Tokens @{ PROJECT_NAME='Foo'; XEX_TYPE='DLL' }
    Assert-Equal 'name=Foo;type=DLL' $out
}
Test-Case 'Get-UnresolvedTokens finds leftover tokens' {
    $left = Get-UnresolvedTokens -Text 'a=@DONE@ b=@MISSING@'
    Assert-True ($left -contains '@MISSING@')
}
Test-Case 'Get-UnresolvedTokens returns empty when fully rendered' {
    $left = Get-UnresolvedTokens -Text 'all good, no tokens here'
    Assert-True ($left.Count -eq 0)
}
Test-Case 'Test-ProjectName accepts a legal name' { Assert-True (Test-ProjectName 'MyGame_01') }
Test-Case 'Test-ProjectName rejects a leading digit' { Assert-True (-not (Test-ProjectName '1bad')) }
Test-Case 'Test-ProjectName rejects spaces/dashes' { Assert-True (-not (Test-ProjectName 'my game')) }

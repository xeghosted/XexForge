$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_TestKit.ps1')
Get-ChildItem $here -Filter '*.Tests.ps1' | Sort-Object Name | ForEach-Object { . $_.FullName }
Write-Host ""
Write-Host ("RESULT: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }

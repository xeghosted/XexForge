$script:Pass = 0
$script:Fail = 0

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Pass++; Write-Host "  PASS  $Name" -ForegroundColor Green }
    catch { $script:Fail++; Write-Host "**FAIL  $Name :: $($_.Exception.Message)" -ForegroundColor Red }
}
function Assert-True   { param($Cond,$Msg='expected true')  if (-not $Cond) { throw $Msg } }
function Assert-Equal  { param($Expected,$Actual)           if ($Expected -ne $Actual) { throw "expected [$Expected], got [$Actual]" } }
function Assert-Throws { param([scriptblock]$Body,$Msg='expected throw') try { & $Body } catch { return } ; throw $Msg }

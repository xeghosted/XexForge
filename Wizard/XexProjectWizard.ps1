[CmdletBinding()] param()

try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch {}
try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here 'XexScaffold.psm1') -Force
$ToolkitRoot = Split-Path -Parent $here

# ---- DWM P/Invoke -----------------------------------------------------------
try {
    Add-Type -Namespace Native -Name Dwm -MemberDefinition '[System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr h,int a,ref int v,int s);'
} catch {}

# ---- accent / palette helpers -----------------------------------------------
function Get-AccentColor {
    # 1) Authoritative system accent (matches native controls) via WinRT UISettings
    try {
        $null = [Windows.UI.ViewManagement.UISettings, Windows.UI.ViewManagement, ContentType=WindowsRuntime]
        $ui = New-Object Windows.UI.ViewManagement.UISettings
        $c  = $ui.GetColorValue([Windows.UI.ViewManagement.UIColorType]::Accent)
        return [System.Drawing.Color]::FromArgb(255, $c.R, $c.G, $c.B)
    } catch {}
    # 2) Registry fallback: Explorer\Accent AccentColorMenu (ABGR DWORD), matches UI accent
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -Name AccentColorMenu -ErrorAction Stop).AccentColorMenu
        return [System.Drawing.Color]::FromArgb(255, ($v -band 0xFF), (($v -shr 8) -band 0xFF), (($v -shr 16) -band 0xFF))
    } catch {}
    # 3) Default Win11 blue
    return [System.Drawing.Color]::FromArgb(255,0,103,192)
}

function Get-AccentHover([System.Drawing.Color]$c) {
    $f = 0.88
    return [System.Drawing.Color]::FromArgb(255,
        [int]([Math]::Max(0,[Math]::Min(255,$c.R*$f))),
        [int]([Math]::Max(0,[Math]::Min(255,$c.G*$f))),
        [int]([Math]::Max(0,[Math]::Min(255,$c.B*$f))))
}

$accent      = Get-AccentColor
$accentHover = Get-AccentHover $accent

# Windows 11 light palette
$clrBg       = [System.Drawing.Color]::FromArgb(255,243,243,243)   # #F3F3F3 window bg
$clrSurface  = [System.Drawing.Color]::FromArgb(255,255,255,255)   # #FFFFFF surface
$clrRail     = [System.Drawing.Color]::FromArgb(255,234,234,234)   # #EAEAEA rail
$clrTextPri  = [System.Drawing.Color]::FromArgb(255,27,27,27)      # #1B1B1B primary text
$clrTextSec  = [System.Drawing.Color]::FromArgb(255,96,96,96)      # #606060 secondary text
$clrDivider  = [System.Drawing.Color]::FromArgb(255,224,224,224)   # #E0E0E0 divider
$clrBtnBdr   = [System.Drawing.Color]::FromArgb(255,208,208,208)   # #D0D0D0 secondary btn border
$clrBtnHov   = [System.Drawing.Color]::FromArgb(255,245,245,245)   # #F5F5F5 secondary hover
$clrSuccess  = [System.Drawing.Color]::FromArgb(255,15,150,50)     # success green
$clrError    = [System.Drawing.Color]::FromArgb(255,180,30,30)     # muted red

$fntTitle    = New-Object System.Drawing.Font('Segoe UI Semibold', 16, [System.Drawing.FontStyle]::Regular)
$fntSubtitle = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
$fntBody     = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
$fntRailAct  = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Regular)
$fntRailInact= New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)

# ---- state ------------------------------------------------------------------
$state = [ordered]@{ Xdk=$null; Generator=$null; Page=0 }

# ---- form -------------------------------------------------------------------
$form = New-Object Windows.Forms.Form
$form.Text            = 'Xbox 360 XEX Project Wizard'
$form.ClientSize      = New-Object Drawing.Size(700,548)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.BackColor       = $clrBg

# ---- left step rail ---------------------------------------------------------
$railWidth = 150
$rail = New-Object Windows.Forms.Panel
$rail.SetBounds(0, 0, $railWidth, 460)
$rail.BackColor = $clrRail
$form.Controls.Add($rail)

$stepNames = @('Prerequisites','Project','Review','Done')
$railLabels = @()
$railPips   = @()   # narrow panels acting as pip

for ($si = 0; $si -lt 4; $si++) {
    $pip = New-Object Windows.Forms.Panel
    $pip.SetBounds(0, (40 + $si * 38), 4, 22)
    $pip.BackColor = $clrRail
    $rail.Controls.Add($pip)
    $railPips += $pip

    $rl = New-Object Windows.Forms.Label
    $rl.SetBounds(12, (40 + $si * 38), ($railWidth - 16), 22)
    $rl.Text      = $stepNames[$si]
    $rl.Font      = $fntRailInact
    $rl.ForeColor = $clrTextSec
    $rl.BackColor = [System.Drawing.Color]::Transparent
    $rail.Controls.Add($rl)
    $railLabels += $rl
}

function Update-Rail($pageIdx) {
    for ($si = 0; $si -lt 4; $si++) {
        if ($si -eq $pageIdx) {
            $railLabels[$si].Font      = $fntRailAct
            $railLabels[$si].ForeColor = $clrTextPri
            $railPips[$si].BackColor   = $accent
        } else {
            $railLabels[$si].Font      = $fntRailInact
            $railLabels[$si].ForeColor = $clrTextSec
            $railPips[$si].BackColor   = $clrRail
        }
    }
}

# ---- content area -----------------------------------------------------------
$contentLeft = $railWidth
$contentW    = 700 - $railWidth   # 550
$contentH    = 460   # above nav bar

# rail divider line
$divPanel = New-Object Windows.Forms.Panel
$divPanel.SetBounds($railWidth, 0, 1, $contentH)
$divPanel.BackColor = $clrDivider
$form.Controls.Add($divPanel)

# content panels (one per page)
$panels = @()
for ($i = 0; $i -lt 4; $i++) {
    $p = New-Object Windows.Forms.Panel
    $p.SetBounds($contentLeft, 0, $contentW, $contentH)
    $p.Visible   = $false
    $p.BackColor = $clrBg
    $form.Controls.Add($p)
    $panels += $p
}

# ---- helper: styled label ---------------------------------------------------
function Add-Label($panel,$text,$x,$y,$w=490,$h=22) {
    $l = New-Object Windows.Forms.Label
    $l.SetBounds($x,$y,$w,$h)
    $l.Text      = $text
    $l.Font      = $fntBody
    $l.ForeColor = $clrTextPri
    $l.BackColor = [System.Drawing.Color]::Transparent
    $panel.Controls.Add($l)
    return $l
}

function Add-PageHeader($panel,$title,$subtitle) {
    $lT = New-Object Windows.Forms.Label
    $lT.SetBounds(28, 22, 490, 30)
    $lT.Text      = $title
    $lT.Font      = $fntTitle
    $lT.ForeColor = $clrTextPri
    $lT.BackColor = [System.Drawing.Color]::Transparent
    $panel.Controls.Add($lT)

    $lS = New-Object Windows.Forms.Label
    $lS.SetBounds(28, 52, 490, 20)
    $lS.Text      = $subtitle
    $lS.Font      = $fntSubtitle
    $lS.ForeColor = $clrTextSec
    $lS.BackColor = [System.Drawing.Color]::Transparent
    $panel.Controls.Add($lS)

    # thin divider under header
    $d = New-Object Windows.Forms.Panel
    $d.SetBounds(28, 76, 470, 1)
    $d.BackColor = $clrDivider
    $panel.Controls.Add($d)
}

# ---- helper: styled textbox -------------------------------------------------
function New-StyledTextBox($x,$y,$w,$h=28) {
    $t = New-Object Windows.Forms.TextBox
    $t.SetBounds($x,$y,$w,$h)
    $t.Font      = $fntBody
    $t.ForeColor = $clrTextPri
    $t.BackColor = $clrSurface
    return $t
}

# ---- helper: styled button (flat) ------------------------------------------
function New-StyledButton($text,$x,$y,$w=110,$h=34,$style='secondary') {
    $b = New-Object Windows.Forms.Button
    $b.SetBounds($x,$y,$w,$h)
    $b.Text      = $text
    $b.Font      = $fntBody
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.Cursor    = [System.Windows.Forms.Cursors]::Hand

    if ($style -eq 'primary') {
        $b.BackColor = $accent
        $b.ForeColor = [System.Drawing.Color]::White
        $b.FlatAppearance.BorderSize      = 0
        $b.FlatAppearance.MouseOverBackColor = $accentHover
    } elseif ($style -eq 'cancel') {
        $b.BackColor = [System.Drawing.Color]::Transparent
        $b.ForeColor = $clrTextSec
        $b.FlatAppearance.BorderSize      = 0
        $b.FlatAppearance.MouseOverBackColor = $clrBtnHov
    } else {
        # secondary
        $b.BackColor = $clrSurface
        $b.ForeColor = $clrTextPri
        $b.FlatAppearance.BorderSize      = 1
        $b.FlatAppearance.BorderColor     = $clrBtnBdr
        $b.FlatAppearance.MouseOverBackColor = $clrBtnHov
    }
    return $b
}

# =============================================================================
# Page 0: Prerequisites
# =============================================================================
Add-PageHeader $panels[0] 'Prerequisites' 'Checking your build environment'

$lblPre   = Add-Label $panels[0] 'Checking prerequisites...' 28 94 490 22
$lblXdk   = Add-Label $panels[0] '' 28 128 490 22
$lblTools = Add-Label $panels[0] '' 28 156 490 22
$lblCmake = Add-Label $panels[0] '' 28 184 490 22
$lblGen   = Add-Label $panels[0] '' 28 212 490 22

$btnBrowseXdk = New-StyledButton 'Locate XDK...' 28 248 130 32 'secondary'
$panels[0].Controls.Add($btnBrowseXdk)

function Set-StatusLabel($lbl,$text,$ok) {
    if ($ok -eq $true) {
        $lbl.Text      = [char]0x2713 + ' ' + $text
        $lbl.ForeColor = $clrSuccess
    } elseif ($ok -eq $false) {
        $lbl.Text      = [char]0x2715 + ' ' + $text
        $lbl.ForeColor = $clrError
    } else {
        $lbl.Text      = $text
        $lbl.ForeColor = $clrTextSec
    }
}

function Refresh-Prereqs {
    $xdk = Find-Xdk -Override $state.Xdk
    $state.Xdk = $xdk
    $okTools = $false
    if ($xdk) {
        Set-StatusLabel $lblXdk "XDK: $xdk" $true
        $t = Test-XdkTools -XdkRoot $xdk
        $okTools = ($t.Cl -and $t.Link -and $t.Imagexex)
        Set-StatusLabel $lblTools "Tools (cl/link/imagexex): $(if ($okTools){'OK'}else{'MISSING'})" $okTools
    } else {
        Set-StatusLabel $lblXdk 'XDK: NOT FOUND   -  click "Locate XDK..." or set %XEDK%' $false
        Set-StatusLabel $lblTools 'Tools: --' $null
    }
    $cm = Test-CMake
    Set-StatusLabel $lblCmake "CMake: $(if ($cm){ $cm }else{ 'NOT FOUND  -  install from cmake.org and add to PATH' })" ([bool]$cm)
    $state.Generator = Find-Generator
    Set-StatusLabel $lblGen "Generator: $(if ($state.Generator){ $state.Generator }else{ 'NONE  -  install Ninja, or run from a VS/XDK dev prompt for NMake' })" ([bool]$state.Generator)
    $script:PrereqsOK = [bool]($xdk -and $okTools -and $cm -and $state.Generator)
    Update-Nav
}

$btnBrowseXdk.Add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq 'OK') { $state.Xdk = $dlg.SelectedPath; Refresh-Prereqs }
})

# =============================================================================
# Page 1: Project settings
# =============================================================================
Add-PageHeader $panels[1] 'Project' 'Configure your new XEX project'

$rowY = 94
[void](Add-Label $panels[1] 'Project name:' 28 ($rowY+3) 120)
$txtName = New-StyledTextBox 156 $rowY 300
$panels[1].Controls.Add($txtName)

$rowY += 40
[void](Add-Label $panels[1] 'Type:' 28 ($rowY+3) 120)
$rbDll = New-Object Windows.Forms.RadioButton
$rbDll.SetBounds(156,$rowY,120,26); $rbDll.Text='XEX-DLL'; $rbDll.Checked=$true
$rbDll.Font=$fntBody; $rbDll.ForeColor=$clrTextPri; $rbDll.BackColor=[System.Drawing.Color]::Transparent
$rbExe = New-Object Windows.Forms.RadioButton
$rbExe.SetBounds(284,$rowY,120,26); $rbExe.Text='XEX-EXE'
$rbExe.Font=$fntBody; $rbExe.ForeColor=$clrTextPri; $rbExe.BackColor=[System.Drawing.Color]::Transparent
$panels[1].Controls.AddRange(@($rbDll,$rbExe))

$rowY += 40
$lblEntry = Add-Label $panels[1] 'Entry symbol:' 28 ($rowY+3) 120
$txtEntry = New-StyledTextBox 156 $rowY 300; $txtEntry.Text='GtampEntryPoint'
$panels[1].Controls.Add($txtEntry)

$rowY += 40
[void](Add-Label $panels[1] 'Create in folder:' 28 ($rowY+3) 120)
$txtDir = New-StyledTextBox 156 $rowY 270
$panels[1].Controls.Add($txtDir)
$btnDir = New-StyledButton 'Browse...' 432 $rowY 80 28 'secondary'
$panels[1].Controls.Add($btnDir)
$btnDir.Add_Click({ $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $txtDir.Text = $d.SelectedPath } })

$rowY += 40
$chkXke = New-Object Windows.Forms.CheckBox
$chkXke.SetBounds(156,$rowY,200,26); $chkXke.Text='Use xkelib'
$chkXke.Font=$fntBody; $chkXke.ForeColor=$clrTextPri; $chkXke.BackColor=[System.Drawing.Color]::Transparent
$panels[1].Controls.Add($chkXke)

$rowY += 32
$txtXke = New-StyledTextBox 156 $rowY 270; $txtXke.Enabled=$false
$panels[1].Controls.Add($txtXke)
$btnXke = New-StyledButton 'Browse...' 432 $rowY 80 28 'secondary'; $btnXke.Enabled=$false
$panels[1].Controls.Add($btnXke)
$btnXke.Add_Click({ $d = New-Object Windows.Forms.FolderBrowserDialog; if ($d.ShowDialog() -eq 'OK') { $txtXke.Text = $d.SelectedPath } })

$rbDll.Add_CheckedChanged({ $lblEntry.Enabled = $rbDll.Checked; $txtEntry.Enabled = $rbDll.Checked })
$chkXke.Add_CheckedChanged({ $txtXke.Enabled = $chkXke.Checked; $btnXke.Enabled = $chkXke.Checked })

# =============================================================================
# Page 2: Review / summary
# =============================================================================
Add-PageHeader $panels[2] 'Review' 'Confirm your project settings before creation'

$lblSummary = New-Object Windows.Forms.Label
$lblSummary.SetBounds(28, 94, 490, 320)
$lblSummary.AutoSize  = $false
$lblSummary.Font      = $fntBody
$lblSummary.ForeColor = $clrTextPri
$lblSummary.BackColor = [System.Drawing.Color]::Transparent
$panels[2].Controls.Add($lblSummary)

# =============================================================================
# Page 3: Done
# =============================================================================
Add-PageHeader $panels[3] 'Done' 'Your project has been created'

$lblDone = New-Object Windows.Forms.Label
$lblDone.SetBounds(28, 94, 490, 80)
$lblDone.AutoSize  = $false
$lblDone.Font      = $fntBody
$lblDone.ForeColor = $clrTextPri
$lblDone.BackColor = [System.Drawing.Color]::Transparent
$panels[3].Controls.Add($lblDone)

$btnOpen        = New-StyledButton 'Open folder'      28  180  110 30 'secondary'
$btnConfigure   = New-StyledButton 'Configure'        146 180  110 30 'secondary'
$btnConfigBuild = New-StyledButton 'Configure + Build' 264 180  140 30 'secondary'
$panels[3].Controls.Add($btnOpen)
$panels[3].Controls.Add($btnConfigure)
$panels[3].Controls.Add($btnConfigBuild)

$txtLog = New-Object Windows.Forms.TextBox
$txtLog.SetBounds(28, 220, 490, 210)
$txtLog.Multiline  = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly   = $true
$txtLog.Font       = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.BackColor  = $clrSurface
$txtLog.ForeColor  = $clrTextPri
$panels[3].Controls.Add($txtLog)

# ---- nav button bar ---------------------------------------------------------
$navBar = New-Object Windows.Forms.Panel
$navBar.SetBounds(0, 460, 700, 88)
$navBar.BackColor = $clrBg
$form.Controls.Add($navBar)

# top border of nav bar
$navDiv = New-Object Windows.Forms.Panel
$navDiv.SetBounds(0, 460, 700, 1)
$navDiv.BackColor = $clrDivider
$form.Controls.Add($navDiv)

$btnBack   = New-StyledButton 'Back'   386 27 110 34 'secondary'
$btnNext   = New-StyledButton 'Next'   502 27 110 34 'primary'
$btnCancel = New-StyledButton 'Cancel' 270 27 110 34 'cancel'
$navBar.Controls.AddRange(@($btnBack,$btnNext,$btnCancel))

$btnCancel.Add_Click({ $form.Close() })

$script:Created = $null

function Show-Page($n) {
    for ($i=0;$i -lt 4;$i++){ $panels[$i].Visible = ($i -eq $n) }
    $state.Page = $n
    Update-Rail $n
    if ($n -eq 0) { Refresh-Prereqs }
    if ($n -eq 2) {
        $type = if ($rbDll.Checked){'DLL'}else{'EXE'}
        $lblSummary.Text = @"
About to create:

  Name:      $($txtName.Text)
  Type:      XEX-$type
  Folder:    $(Join-Path $txtDir.Text $txtName.Text)
  Generator: $($state.Generator)
  xkelib:    $(if($chkXke.Checked){"yes  ($($txtXke.Text))"}else{'no'})

Click Create to generate the project.
"@
    }
    Update-Nav
}

function Update-Nav {
    $btnBack.Enabled = ($state.Page -gt 0 -and $state.Page -lt 3)
    switch ($state.Page) {
        0 { $btnNext.Text='Next';   $btnNext.Enabled = [bool]$script:PrereqsOK }
        1 { $btnNext.Text='Next';   $btnNext.Enabled = (Test-ProjectName $txtName.Text) -and [bool]$txtDir.Text -and ((-not $chkXke.Checked) -or [bool]$txtXke.Text) }
        2 { $btnNext.Text='Create'; $btnNext.Enabled = $true }
        3 { $btnNext.Text='Close';  $btnNext.Enabled = $true; $btnBack.Enabled=$false }
    }
    # Keep primary button styled correctly after text change
    $btnNext.BackColor = $accent
    $btnNext.ForeColor = [System.Drawing.Color]::White
    $btnNext.FlatAppearance.BorderSize = 0
    $btnNext.FlatAppearance.MouseOverBackColor = $accentHover
}

$txtName.Add_TextChanged({ Update-Nav }); $txtDir.Add_TextChanged({ Update-Nav })
$chkXke.Add_CheckedChanged({ Update-Nav }); $txtXke.Add_TextChanged({ Update-Nav })

$btnBack.Add_Click({ if ($state.Page -gt 0) { Show-Page ($state.Page-1) } })
$btnNext.Add_Click({
    switch ($state.Page) {
        0 { Show-Page 1 }
        1 { Show-Page 2 }
        2 {
            try {
                $type = if ($rbDll.Checked){'DLL'}else{'EXE'}
                $r = New-XexProject -Name $txtName.Text -Type $type -TargetDir $txtDir.Text `
                        -ToolkitRoot $ToolkitRoot -EntrySymbol $txtEntry.Text `
                        -UseXkelib:$chkXke.Checked -XkelibDir $txtXke.Text -Generator $state.Generator
                $script:Created = $r
                $lblDone.Text = "Created $($r.Files.Count) files in:`r`n$($r.ProjectDir)`r`n`r`nBuild it with:  cmake --preset xdk  &&  cmake --build build"
                $txtLog.Text = ($r.Files -join "`r`n")
                Show-Page 3
            } catch {
                [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Generation failed','OK','Error') | Out-Null
            }
        }
        3 { $form.Close() }
    }
})
$btnOpen.Add_Click({ if ($script:Created) { Start-Process explorer.exe $script:Created.ProjectDir } })
$btnConfigure.Add_Click({
    if (-not $script:Created) { [Windows.Forms.MessageBox]::Show('No project created yet.','Configure','OK','Warning') | Out-Null; return }
    Push-Location $script:Created.ProjectDir
    $out = & cmake --preset xdk 2>&1 | Out-String
    Pop-Location
    $txtLog.AppendText("`r`n-- Configure --`r`n$out")
})
$btnConfigBuild.Add_Click({
    if (-not $script:Created) { [Windows.Forms.MessageBox]::Show('No project created yet.','Configure + Build','OK','Warning') | Out-Null; return }
    Push-Location $script:Created.ProjectDir
    $out = & cmake --preset xdk 2>&1 | Out-String
    $txtLog.AppendText("`r`n-- Configure --`r`n$out")
    if ($LASTEXITCODE -eq 0) {
        $out2 = & cmake --build build 2>&1 | Out-String
        $txtLog.AppendText("`r`n-- Build --`r`n$out2")
    }
    Pop-Location
})

# ---- DWM / Win11 chrome (after handle exists) --------------------------------
$form.Add_Shown({
    try {
        $h = $form.Handle
        # Rounded corners (attr 33, value 2 = round)
        $v = 2; [Native.Dwm]::DwmSetWindowAttribute($h, 33, [ref]$v, 4) | Out-Null
    } catch {}
    try {
        # Dark mode title bar: 1 if system uses dark theme, else 0
        $appsLight = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme
        $darkVal = if ($appsLight -eq 0) { 1 } else { 0 }
        [Native.Dwm]::DwmSetWindowAttribute($form.Handle, 20, [ref]$darkVal, 4) | Out-Null
    } catch {}
    try {
        # Mica backdrop (attr 38, value 2)
        $m = 2; [Native.Dwm]::DwmSetWindowAttribute($form.Handle, 38, [ref]$m, 4) | Out-Null
    } catch {}
})

Show-Page 0
if (-not $global:XEXWIZ_NOSHOW) { [void]$form.ShowDialog() }

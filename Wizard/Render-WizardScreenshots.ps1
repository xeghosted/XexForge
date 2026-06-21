# Render-WizardScreenshots.ps1
# Dot-sources the wizard (suppressing ShowDialog) and saves PNG screenshots for all 4 pages.
param()

$outDir = 'C:\Users\BBC\Desktop\Projects\xex-cmake-template\.reports'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Suppress ShowDialog when dot-sourcing
$global:XEXWIZ_NOSHOW = $true

# Dot-source the wizard to build the form
. (Join-Path $PSScriptRoot 'XexProjectWizard.ps1')

# Show the form offscreen so DrawToBitmap paints controls properly
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(-9999, -9999)
$form.Show()
[System.Windows.Forms.Application]::DoEvents()

for ($pg = 0; $pg -lt 4; $pg++) {
    Show-Page $pg
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    $bmp = New-Object System.Drawing.Bitmap($form.ClientSize.Width, $form.ClientSize.Height)
    $form.DrawToBitmap($bmp, [System.Drawing.Rectangle]::new(0, 0, $form.ClientSize.Width, $form.ClientSize.Height))

    $outPath = Join-Path $outDir "ui-page$pg.png"
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "Saved: $outPath ($($form.ClientSize.Width)x$($form.ClientSize.Height))"
}

$form.Close()
$form.Dispose()
$global:XEXWIZ_NOSHOW = $false
Write-Host 'Done.'

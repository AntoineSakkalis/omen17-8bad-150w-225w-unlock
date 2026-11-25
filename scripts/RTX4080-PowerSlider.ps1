Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Common-Paths.ps1')

$rootDir    = Get-RepoRoot
$nvpwrDir   = Join-Path $rootDir 'nvpwr'
$ctlPath    = Join-Path $nvpwrDir 'NvpwrCtl.exe'
$sysPath    = Join-Path $nvpwrDir 'Nvpwr.sys'
$guiPath    = Join-Path $nvpwrDir 'NvpwrControl.exe'
$targetFile = Join-Path $rootDir 'saved_target.txt'

if (-not ((Test-Path -LiteralPath $ctlPath) -and (Test-Path -LiteralPath $sysPath))) {
    [System.Windows.Forms.MessageBox]::Show("Missing NvpwrCtl.exe / Nvpwr.sys in $nvpwrDir.`nDownload NvpwrControl first (see nvpwr\README.md).", "NvpwrControl Missing", 'OK', 'Warning') | Out-Null
    exit 1
}

# Elevate only if Nvpwr driver service is not already running
$svc = Get-Service -Name 'Nvpwr' -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne 'Running') {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
    if (-not $svc) {
        sc.exe create Nvpwr type= kernel start= demand binPath= "$sysPath" DisplayName= "Nvpwr GPU Power Control" | Out-Null
    }
    sc.exe start Nvpwr | Out-Null
    Start-Sleep -Milliseconds 500
}

function Get-NvpwrStatus {
    $out = (& $ctlPath status 2>&1) -join "`n"
    $state = if ($out -match 'State\s*:\s*([A-Z_]+)') { $Matches[1] } else { 'UNKNOWN' }
    $curr  = if ($out -match 'Current effective\s*:\s*\d+\s*\(([\d\.]+)\s*W\)') { [double]$Matches[1] } else { 175.0 }
    $max   = if ($out -match 'MAX effective\s*:\s*\d+\s*\(([\d\.]+)\s*W\)') { [double]$Matches[1] } else { 175.0 }
    return [PSCustomObject]@{ Raw = $out; State = $state; CurrentW = $curr; MaxW = $max }
}

function Apply-Wattage([int]$watts) {
    $st = Get-NvpwrStatus
    $cmdOut = ''
    if ($st.State -eq 'MIXED') {
        $lblStatus.Text = "Normalizing NVPCF baseline (brief Power saver dip)..."
        $lblStatus.ForeColor = [System.Drawing.Color]::Gold
        $form.Refresh()
        & $ctlPath restore | Out-Null
        Start-Sleep -Milliseconds 150
        $check0 = Get-NvpwrStatus
        if ($check0.State -eq 'STOCK_BASELINE' -or $check0.State -eq 'APPLIED') {
            $cmdOut = (& $ctlPath set 4080 $watts 2>&1) -join ' '
        } else {
            $active = ((powercfg /getactivescheme) | Select-String '([0-9a-f-]{36})').Matches.Groups[1].Value
            $pwrSaver = '162e1a7b-6914-4ca1-b348-634f73e08a53'
            try {
                powercfg /setactive $pwrSaver
                for ($i = 0; $i -lt 24; $i++) {
                    Start-Sleep -Milliseconds 250
                    $check = Get-NvpwrStatus
                    if ($check.State -eq 'STOCK_BASELINE' -or $check.State -eq 'APPLIED') { break }
                }
                $cmdOut = (& $ctlPath set 4080 $watts 2>&1) -join ' '
            } finally {
                if ($active) { powercfg /setactive $active }
            }
        }
    } else {
        $cmdOut = (& $ctlPath set 4080 $watts 2>&1) -join ' '
    }
    if ($cmdOut -match 'failed|error') {
        $lblStatus.Text = "Error setting ${watts}W: $cmdOut"
        $lblStatus.ForeColor = [System.Drawing.Color]::Salmon
    } else {
        Set-Content -Path $targetFile -Value "$watts" -Encoding Ascii
        Update-Telemetry
    }
}

function Restore-Stock {
    & $ctlPath restore | Out-Null
    Set-Content -Path $targetFile -Value 'STOCK' -Encoding Ascii
    $slider.Value = 35
    $lblTarget.Text = "175 W"
    Update-Telemetry
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text = "RTX 4080 Laptop - TGP Power Limit Slider (150W - 225W)"
$form.Size = New-Object System.Drawing.Size(500, 340)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(22, 24, 30)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "NVIDIA RTX 4080 Laptop TGP Unlocker"
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(118, 185, 0)
$lblTitle.Location = New-Object System.Drawing.Point(20, 14)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$lblTarget = New-Object System.Windows.Forms.Label
$lblTarget.Text = "225 W"
$lblTarget.Font = New-Object System.Drawing.Font('Segoe UI Bold', 22)
$lblTarget.ForeColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
$lblTarget.Location = New-Object System.Drawing.Point(365, 8)
$lblTarget.Size = New-Object System.Drawing.Size(110, 42)
$lblTarget.TextAlign = 'TopRight'
$form.Controls.Add($lblTarget)

$lblTelemetry = New-Object System.Windows.Forms.Label
$lblTelemetry.Text = "Reading live GPU telemetry..."
$lblTelemetry.Font = New-Object System.Drawing.Font('Consolas', 10)
$lblTelemetry.ForeColor = [System.Drawing.Color]::FromArgb(210, 215, 225)
$lblTelemetry.BackColor = [System.Drawing.Color]::FromArgb(32, 36, 46)
$lblTelemetry.Location = New-Object System.Drawing.Point(20, 52)
$lblTelemetry.Size = New-Object System.Drawing.Size(445, 48)
$lblTelemetry.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
$form.Controls.Add($lblTelemetry)

$slider = New-Object System.Windows.Forms.TrackBar
$slider.Minimum = 30
$slider.Maximum = 45
$slider.TickFrequency = 1
$slider.SmallChange = 1
$slider.LargeChange = 2
$slider.Value = 45
$slider.Location = New-Object System.Drawing.Point(16, 112)
$slider.Size = New-Object System.Drawing.Size(452, 45)
$slider.BackColor = [System.Drawing.Color]::FromArgb(22, 24, 30)
$slider.Add_ValueChanged({
    $w = $slider.Value * 5
    $lblTarget.Text = "$w W"
    if ($w -le 175) {
        $lblTarget.ForeColor = [System.Drawing.Color]::FromArgb(118, 185, 0)
    } elseif ($w -le 205) {
        $lblTarget.ForeColor = [System.Drawing.Color]::FromArgb(0, 212, 255)
    } else {
        $lblTarget.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
    }
})
$form.Controls.Add($slider)

$lblScale = New-Object System.Windows.Forms.Label
$lblScale.Text = "150W             175W (Stock)            200W                  225W"
$lblScale.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$lblScale.ForeColor = [System.Drawing.Color]::FromArgb(150, 155, 165)
$lblScale.Location = New-Object System.Drawing.Point(22, 154)
$lblScale.Size = New-Object System.Drawing.Size(445, 18)
$form.Controls.Add($lblScale)

$presets = @(175, 185, 195, 200, 210, 225)
$x = 20
foreach ($p in $presets) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "${p}W"
    $btn.Tag = $p
    $btn.Location = New-Object System.Drawing.Point($x, 180)
    $btn.Size = New-Object System.Drawing.Size(69, 30)
    $btn.FlatStyle = 'Flat'
    $btn.BackColor = [System.Drawing.Color]::FromArgb(38, 43, 56)
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.Add_Click({
        $w = [int]$this.Tag
        $slider.Value = [int]($w / 5)
        Apply-Wattage $w
    })
    $form.Controls.Add($btn)
    $x += 75
}

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "Apply Slider Wattage"
$btnApply.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$btnApply.Location = New-Object System.Drawing.Point(20, 222)
$btnApply.Size = New-Object System.Drawing.Size(215, 38)
$btnApply.FlatStyle = 'Flat'
$btnApply.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
$btnApply.ForeColor = [System.Drawing.Color]::White
$btnApply.Add_Click({ Apply-Wattage ($slider.Value * 5) })
$form.Controls.Add($btnApply)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = "Restore Stock (175W)"
$btnRestore.Location = New-Object System.Drawing.Point(245, 222)
$btnRestore.Size = New-Object System.Drawing.Size(135, 38)
$btnRestore.FlatStyle = 'Flat'
$btnRestore.BackColor = [System.Drawing.Color]::FromArgb(55, 60, 72)
$btnRestore.ForeColor = [System.Drawing.Color]::White
$btnRestore.Add_Click({ Restore-Stock })
$form.Controls.Add($btnRestore)

$btnFullGui = New-Object System.Windows.Forms.Button
$btnFullGui.Text = "Full GUI"
$btnFullGui.Location = New-Object System.Drawing.Point(388, 222)
$btnFullGui.Size = New-Object System.Drawing.Size(77, 38)
$btnFullGui.FlatStyle = 'Flat'
$btnFullGui.BackColor = [System.Drawing.Color]::FromArgb(45, 50, 62)
$btnFullGui.ForeColor = [System.Drawing.Color]::LightGray
$btnFullGui.Add_Click({
    if (Test-Path -LiteralPath $guiPath) { Start-Process -FilePath $guiPath -Verb RunAs }
})
$form.Controls.Add($btnFullGui)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready."
$lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(140, 220, 140)
$lblStatus.Location = New-Object System.Drawing.Point(20, 270)
$lblStatus.Size = New-Object System.Drawing.Size(445, 22)
$form.Controls.Add($lblStatus)

function Update-Telemetry {
    try {
        $st = Get-NvpwrStatus
        $smi = (nvidia-smi --query-gpu=temperature.gpu,power.draw,enforced.power.limit,power.max_limit,clocks.gr,clocks.mem --format=csv,noheader,nounits 2>$null)
        if ($smi) {
            $parts = $smi.Split(',') | ForEach-Object { $_.Trim() }
            $lblTelemetry.Text = "Draw: $($parts[1]) W / $($parts[2]) W (Max $($parts[3]) W) | Temp: $($parts[0]) C`r`nCore: $($parts[4]) MHz | Mem: $($parts[5]) MHz | Policy: $($st.State)"
            $lblStatus.Text = "Active limit: $([int]$st.MaxW) W ($($st.State))"
            $lblStatus.ForeColor = if ($st.State -eq 'APPLIED') { [System.Drawing.Color]::FromArgb(120, 230, 140) } else { [System.Drawing.Color]::Silver }
        }
    } catch {}
}

$initSt = Get-NvpwrStatus
if ($initSt.MaxW -ge 150 -and $initSt.MaxW -le 225) {
    $slider.Value = [int]([math]::Round($initSt.MaxW / 5))
}
Update-Telemetry

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1500
$timer.Add_Tick({ Update-Telemetry })
$timer.Start()

$form.Add_FormClosing({ $timer.Stop(); $timer.Dispose() })
[void]$form.ShowDialog()

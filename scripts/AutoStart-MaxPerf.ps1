#Requires -RunAsAdministrator
param(
    [switch]$BootDelay
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Common-Paths.ps1')

$rootDir    = Get-RepoRoot
$nvpwrDir   = Join-Path $rootDir 'nvpwr'
$ctlPath    = Join-Path $nvpwrDir 'NvpwrCtl.exe'
$sysPath    = Join-Path $nvpwrDir 'Nvpwr.sys'
$targetFile = Join-Path $rootDir 'saved_target.txt'
$logPath    = Join-Path $rootDir 'autostart.log'

$omenExe = Find-OmenMonExe
$omenXml = if ($omenExe) { Join-Path (Split-Path -Parent $omenExe) 'OmenMon.xml' } else { $null }
$tsExe   = Find-ThrottleStopExe

$hiPerf  = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$pwrSave = '162e1a7b-6914-4ca1-b348-634f73e08a53'

function Write-AutoLog([string]$msg) {
    Add-Content -LiteralPath $logPath -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
}

Set-Content -LiteralPath $logPath -Value ("=== AutoStart-MaxPerf started at {0} ===" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8

# 1. Wait 12 seconds at logon so OmenMon and MSI Afterburner finish initializing first
if ($BootDelay) {
    Start-Sleep -Seconds 12
}

# 2. Ensure OmenMon-Reborn watchdog settings prevent 1-min GPU fan drops & 6-min dual-fan drops
if ($omenXml -and (Test-Path -LiteralPath $omenXml)) {
    $xmlRaw = Get-Content -LiteralPath $omenXml -Raw -Encoding UTF8
    $changed = $false
    if ($xmlRaw -match '<FanProgramModeCheckFirst>true</FanProgramModeCheckFirst>') {
        $xmlRaw = $xmlRaw -replace '<FanProgramModeCheckFirst>true</FanProgramModeCheckFirst>', '<FanProgramModeCheckFirst>false</FanProgramModeCheckFirst>'
        $changed = $true
    }
    if ($xmlRaw -match '<FanProgramSharedTemperature>false</FanProgramSharedTemperature>') {
        $xmlRaw = $xmlRaw -replace '<FanProgramSharedTemperature>false</FanProgramSharedTemperature>', '<FanProgramSharedTemperature>true</FanProgramSharedTemperature>'
        $changed = $true
    }
    if ($changed) {
        Get-Process -Name 'OmenMon' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        [System.IO.File]::WriteAllText($omenXml, $xmlRaw, (New-Object System.Text.UTF8Encoding($false)))
        Write-AutoLog "Patched OmenMon.xml watchdog settings (ModeCheckFirst=false, SharedTemp=true)."
    }
}

# 3. Ensure OmenMon is running cleanly with updated XML, then unlock BIOS 150W CPU + Performance + Max GPU
if ($omenExe) {
    $omenProc = Get-Process -Name 'OmenMon' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($omenProc -and $omenXml -and (Test-Path $omenXml) -and ((Get-Item $omenXml).LastWriteTime -gt $omenProc.StartTime)) {
        Stop-Process -Id $omenProc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        $omenProc = $null
    }
    if (-not $omenProc) {
        Start-ScheduledTask -TaskName 'OmenMon' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }

    $biosSetOut = (cmd.exe /c "`"$omenExe`" -Bios FanMode=Performance Cpu:PL1=150 Gpu=Maximum 2>&1") -join "`r`n"
    Write-AutoLog "--- BIOS SET (FanMode=Performance Cpu:PL1=150 Gpu=Maximum) ---`r`n$biosSetOut"
    Start-Sleep -Seconds 1
} else {
    Write-AutoLog "WARN: OmenMon.exe not found; skipped BIOS 150W/Performance apply."
}

# 4. Restart ThrottleStop so MSR + SyncMMIO enforce 150W + FIVR undervolt/ratios cleanly on top of BIOS
if ($tsExe) {
    Get-Process -Name 'ThrottleStop' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Process -FilePath $tsExe -WorkingDirectory (Split-Path -Parent $tsExe) -WindowStyle Minimized
    Start-Sleep -Seconds 2
    Write-AutoLog "Restarted ThrottleStop: $tsExe"
}

# 5. Apply GPU TGP target via NvpwrCtl (default 225 W, or STOCK/175 skips override)
$savedRaw = if (Test-Path -LiteralPath $targetFile) { (Get-Content -LiteralPath $targetFile -Raw).Trim() } else { '225' }
$opts = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control').SystemStartOptions

if ($savedRaw -match '^(STOCK|175)$') {
    Write-AutoLog "Nvpwr skipped (saved_target=$savedRaw; keeping stock 175W)."
    & powercfg.exe /setactive $hiPerf
} elseif (-not ((Test-Path -LiteralPath $ctlPath) -and (Test-Path -LiteralPath $sysPath))) {
    Write-AutoLog "Nvpwr skipped (extract NvpwrCtl.exe & Nvpwr.sys into nvpwr\ first)."
    & powercfg.exe /setactive $hiPerf
} elseif ($opts -match 'TESTSIGNING') {
    $targetW = if ($savedRaw -match '^\d+$' -and [int]$savedRaw -ge 150 -and [int]$savedRaw -le 225) { [int]$savedRaw } else { 225 }
    $targetMw = $targetW * 1000

    $svc = Get-Service -Name 'Nvpwr' -ErrorAction SilentlyContinue
    if (-not $svc) {
        sc.exe create Nvpwr type= kernel start= demand binPath= "$sysPath" DisplayName= "Nvpwr GPU Power Control" | Out-Null
    } else {
        sc.exe config Nvpwr type= kernel start= demand binPath= "$sysPath" | Out-Null
    }
    sc.exe start Nvpwr | Out-Null
    Start-Sleep -Milliseconds 500

    $stTxt = (& $ctlPath status 2>&1) -join "`n"
    $isLockedTarget = ($stTxt -match 'State\s*:\s*APPLIED') -and ($stTxt -match "Applied target\s*:\s*$targetMw\b")
    if (-not $isLockedTarget) {
        if (($stTxt -match 'State\s*:\s*MIXED') -and ($stTxt -match 'Flags init/elig/amt\s*:\s*1 / 1 / 1')) {
            & $ctlPath restore | Out-Null
            Start-Sleep -Milliseconds 300
        }
        # Briefly dip to Power saver so NVPCF reaches 175.0W STOCK_BASELINE, lock target, then restore High performance
        try {
            & powercfg.exe /setactive $pwrSave
            for ($i = 0; $i -lt 32; $i++) {
                Start-Sleep -Milliseconds 250
                $txt = (& $ctlPath status 2>&1) -join "`n"
                if ($txt -match 'State\s*:\s*(STOCK_BASELINE|APPLIED)') { break }
            }
            $setOut = (& $ctlPath set 4080 $targetW 2>&1) -join "`r`n"
            Write-AutoLog "--- NVPWR SET $targetW ---`r`n$setOut"
        } finally {
            & powercfg.exe /setactive $hiPerf
        }
    } else {
        & powercfg.exe /setactive $hiPerf
    }
    $nvFinal = (& $ctlPath status 2>&1) -join "`r`n"
    Write-AutoLog "--- NVPWR FINAL ---`r`n$nvFinal"
} else {
    Write-AutoLog "Nvpwr skipped (TESTSIGNING is OFF; stock 175W)."
    & powercfg.exe /setactive $hiPerf
}

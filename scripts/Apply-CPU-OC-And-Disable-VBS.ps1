#Requires -RunAsAdministrator
param(
    [ValidateRange(50, 52)]
    [int]$FavoredCoreRatio = 51,
    [int]$OtherPcoreRatio = 50,
    [int]$EcoreRatio = 37
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Common-Paths.ps1')

$rootDir = Get-RepoRoot
$bakDir  = Join-Path $rootDir 'backups'
if (-not (Test-Path -LiteralPath $bakDir)) { New-Item -ItemType Directory -Path $bakDir -Force | Out-Null }

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " i7-13700HX Core 4 & 6 OC (+0.1 GHz) + VBS/Hyper-V Disable Fix" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Disable Windows Hypervisor + VBS / Hyper-V (~3-4% ST/latency overhead + MSR 0x150 FIVR unlock)
Write-Host "[1/4] Disabling Windows Hypervisor, VBS, and Hyper-V features..." -ForegroundColor Yellow
& bcdedit.exe /set hypervisorlaunchtype off
& bcdedit.exe /set vsmlaunchtype Off
& bcdedit.exe /set isolatedcontext No

$regTargets = @(
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'RequirePlatformSecurityFeatures'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name = 'Locked'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Name = 'Enabled'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Name = 'Locked'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard'; Name = 'Enabled'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\KernelShadowStacks'; Name = 'Enabled'; Value = 0 },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'LsaCfgFlags'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'EnableVirtualizationBasedSecurity'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'RequirePlatformSecurityFeatures'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'HypervisorEnforcedCodeIntegrity'; Value = 0 },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'; Name = 'LsaCfgFlags'; Value = 0 }
)
foreach ($r in $regTargets) {
    if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
    New-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Value -PropertyType DWord -Force | Out-Null
}

foreach ($svcName in @('vmms', 'vmcompute', 'HvHost')) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

foreach ($feat in @('Microsoft-Hyper-V-All', 'VirtualMachinePlatform', 'HypervisorPlatform', 'Containers-DisposableClientVM', 'Windows-Defender-ApplicationGuard')) {
    $info = & dism.exe /online /Get-FeatureInfo /FeatureName:$feat 2>&1 | Out-String
    if ($info -match 'State\s*:\s*Enabled') {
        & dism.exe /online /Disable-Feature /FeatureName:$feat /NoRestart | Out-Host
    }
}

# 2. Configure ThrottleStop.ini (Core 4* & 6* = 51x/52x, others = 50x, UsePerCore = 1)
Write-Host "[2/4] Updating ThrottleStop.ini..." -ForegroundColor Yellow
$tsExe = Find-ThrottleStopExe
$tsIni = if ($tsExe) { Join-Path (Split-Path -Parent $tsExe) 'ThrottleStop.ini' } else { $null }

if ($tsIni -and (Test-Path -LiteralPath $tsIni)) {
    Stop-Process -Name 'ThrottleStop' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -Path $tsIni -Destination (Join-Path $bakDir "ThrottleStop.ini.backup-$stamp") -Force

    $hexFav = '{0:X2}' -f $FavoredCoreRatio
    $hexOth = '{0:X2}' -f $OtherPcoreRatio
    $oneAdEax0 = "0x${hexOth}${hexOth}${hexFav}${hexFav}"
    $oneAdEdx0 = "0x${hexOth}${hexOth}${hexOth}${hexOth}"

    $rawLines = [System.IO.File]::ReadAllLines($tsIni)
    $outLines = New-Object System.Collections.Generic.List[string]
    $seenHeader = $false

    foreach ($line in $rawLines) {
        $clean = $line.Trim().TrimStart([char]0xFEFF)
        if ($clean -eq '[ThrottleStop]') {
            if ($seenHeader) { break }
            $seenHeader = $true
            $outLines.Add('[ThrottleStop]')
            continue
        }
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }
        if ($clean -match '^(OneAD_EAX0|OneAD_EDX0|UsePerCore|PerCore[0-8]|CheckSum)=') { continue }
        $outLines.Add($clean)
    }
    if (-not $seenHeader) { $outLines.Insert(0, '[ThrottleStop]') }

    $outLines.Add("OneAD_EAX0=$oneAdEax0")
    $outLines.Add("OneAD_EDX0=$oneAdEdx0")
    $outLines.Add("UsePerCore=1")
    for ($c = 0; $c -le 7; $c++) {
        $ratio = if ($c -eq 4 -or $c -eq 6) { $FavoredCoreRatio } else { $OtherPcoreRatio }
        $outLines.Add("PerCore$c=$ratio")
    }
    $outLines.Add("PerCore8=$EcoreRatio")

    [System.IO.File]::WriteAllText($tsIni, (($outLines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
    Start-Process -FilePath $tsExe -WorkingDirectory (Split-Path -Parent $tsExe) -WindowStyle Minimized
    Start-Sleep -Seconds 3
} else {
    Write-Host "  ThrottleStop.ini not found automatically; apply Turbo Groups / Per Core in ThrottleStop FIVR manually." -ForegroundColor Yellow
}

# 3. Ensure High performance power plan allows 100% on both P-cores (Class 1) and E-cores (Class 0)
Write-Host "[3/4] Ensuring High performance power plan max state = 100% for E-cores & P-cores..." -ForegroundColor Yellow
$hiPerf    = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$subProc   = '54533251-82be-4824-96c1-47b60b740d00'
$maxClass0 = 'bc5038f7-23e0-4960-96da-33abaf5935ec'
$maxClass1 = 'bc5038f7-23e0-4960-96da-33abaf5935ed'

& powercfg.exe /setacvalueindex $hiPerf $subProc $maxClass0 100
& powercfg.exe /setdcvalueindex $hiPerf $subProc $maxClass0 100
& powercfg.exe /setacvalueindex $hiPerf $subProc $maxClass1 100
& powercfg.exe /setdcvalueindex $hiPerf $subProc $maxClass1 100

if (((& powercfg.exe /getactivescheme) -join ' ') -match $hiPerf) {
    & powercfg.exe /setactive $hiPerf
}

# 4. Fix default 72h Scheduled Task kill & battery restrictions
Write-Host "[4/4] Removing 72h timeout / battery limits on ThrottleStop & OmenMon tasks (if present)..." -ForegroundColor Yellow
foreach ($taskName in @('ThrottleStop Startup', 'OmenMon')) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        $s = $task.Settings
        $s.DisallowStartIfOnBatteries = $false
        $s.StopIfGoingOnBatteries     = $false
        $s.ExecutionTimeLimit         = 'PT0S'
        Set-ScheduledTask -TaskName $taskName -Settings $s | Out-Null
    }
}

Write-Host ""
Write-Host "Done! Reboot to unload VBS/Hyper-V and activate unlocked FIVR + Core 4/6 OC." -ForegroundColor Green

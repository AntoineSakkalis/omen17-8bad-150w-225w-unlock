# Shared path auto-detection helpers for HP OMEN 17 (8BAD) tuning scripts

function Get-RepoRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Find-OmenMonExe {
    $candidates = @(
        (Join-Path $env:USERPROFILE 'Desktop\omen\OmenMon.exe'),
        'C:\OmenMon\OmenMon.exe',
        'C:\Program Files\OmenMon\OmenMon.exe',
        (Join-Path (Get-RepoRoot) 'omenmon\OmenMon.exe')
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Find-ThrottleStopExe {
    $candidates = @(
        (Join-Path $env:USERPROFILE 'Desktop\ThrottleStop.exe'),
        'C:\ThrottleStop\ThrottleStop.exe',
        'C:\Program Files\ThrottleStop\ThrottleStop.exe',
        'C:\Program Files (x86)\ThrottleStop\ThrottleStop.exe'
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    $proc = Get-Process -Name 'ThrottleStop' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) { return $proc.Path }
    return $null
}

function Find-AfterburnerDir {
    foreach ($p in @('C:\Program Files (x86)\MSI Afterburner', 'C:\Program Files\MSI Afterburner')) {
        if (Test-Path -LiteralPath (Join-Path $p 'MSIAfterburner.exe')) { return $p }
    }
    return $null
}

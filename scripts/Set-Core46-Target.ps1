#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(50, 52)]
    [int]$FavoredCoreRatio,
    [int]$OtherPcoreRatio = 50,
    [int]$EcoreRatio = 37
)

. (Join-Path $PSScriptRoot 'Common-Paths.ps1')

$tsExe = Find-ThrottleStopExe
$tsIni = if ($tsExe) { Join-Path (Split-Path -Parent $tsExe) 'ThrottleStop.ini' } else { $null }

if (-not ($tsIni -and (Test-Path -LiteralPath $tsIni))) {
    Write-Host "ERROR: ThrottleStop.ini not found automatically." -ForegroundColor Red
    exit 1
}

Stop-Process -Name 'ThrottleStop' -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

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
if ($FavoredCoreRatio -gt $OtherPcoreRatio) {
    $outLines.Add("UsePerCore=1")
    for ($c = 0; $c -le 7; $c++) {
        $ratio = if ($c -eq 4 -or $c -eq 6) { $FavoredCoreRatio } else { $OtherPcoreRatio }
        $outLines.Add("PerCore$c=$ratio")
    }
    $outLines.Add("PerCore8=$EcoreRatio")
} else {
    $outLines.Add("UsePerCore=0")
}

[System.IO.File]::WriteAllText($tsIni, (($outLines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
Write-Host "Updated ThrottleStop.ini -> Core 4 & 6 = ${FavoredCoreRatio}x, Other P-Cores = ${OtherPcoreRatio}x" -ForegroundColor Green

Start-Process -FilePath $tsExe -WorkingDirectory (Split-Path -Parent $tsExe) -WindowStyle Minimized
Start-Sleep -Seconds 4

foreach ($pair in @(@('Core 4', 8, 256), @('Core 6', 12, 4096))) {
    $name, $lp, $mask = $pair[0], $pair[1], $pair[2]
    $p = Start-Process powershell.exe -ArgumentList '-NoProfile -Command "$t=Get-Date; $x=1.0; while((Get-Date)-lt $t.AddSeconds(2.5)){ $x=[math]::Sqrt($x+12345.67) }"' -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 150
    try { $p.ProcessorAffinity = [IntPtr]$mask } catch {}
    $maxF = 0
    for ($i = 0; $i -lt 8; $i++) {
        Start-Sleep -Milliseconds 200
        $s = Get-Counter "\Processor Information(0,$lp)\Actual Frequency" -ErrorAction SilentlyContinue
        if ($s) {
            $v = [math]::Round($s.CounterSamples[0].CookedValue, 0)
            if ($v -gt $maxF) { $maxF = $v }
        }
    }
    $p.WaitForExit(3000) | Out-Null
    Write-Host "Live Peak $name (LP $lp): $maxF MHz" -ForegroundColor Cyan
}

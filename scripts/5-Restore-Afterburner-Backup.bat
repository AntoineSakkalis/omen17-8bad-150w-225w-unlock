@echo off
title Restore Original MSI Afterburner V/F Curve
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "BAK=%~dp0..\backups\afterburner_backup.cfg"

if not exist "%BAK%" (
    echo [!] No backup found at %BAK%
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ab = @('C:\Program Files (x86)\MSI Afterburner','C:\Program Files\MSI Afterburner') | Where-Object { Test-Path (Join-Path $_ 'MSIAfterburner.exe') } | Select-Object -First 1; " ^
    "if (-not $ab) { Write-Host '[!] MSI Afterburner not found.' -ForegroundColor Red; exit 1 }; " ^
    "$profDir = Join-Path $ab 'Profiles'; " ^
    "$targetCfg = Get-ChildItem $profDir -Filter 'VEN_10DE&DEV_27E0*.cfg' -ErrorAction SilentlyContinue | Select-Object -First 1; " ^
    "if (-not $targetCfg) { $dest = Join-Path $profDir 'VEN_10DE&DEV_27E0&SUBSYS_8BAD103C&REV_A1&BUS_1&DEV_0&FN_0.cfg' } else { $dest = $targetCfg.FullName }; " ^
    "Stop-Process -Name 'MSIAfterburner' -Force -ErrorAction SilentlyContinue; " ^
    "Start-Sleep -Seconds 2; " ^
    "Copy-Item '%BAK%' $dest -Force; " ^
    "Start-Process -FilePath (Join-Path $ab 'MSIAfterburner.exe') -ArgumentList '-profile1'; " ^
    "Write-Host 'Original MSI Afterburner profile restored!' -ForegroundColor Green"
echo.
pause

@echo off
title Apply Tuned MSI Afterburner RTX 4080 Laptop V/F Curve
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "ROOT=%~dp0.."
set "CFGDIR=%ROOT%\configs\afterburner"
set "BAKDIR=%ROOT%\backups"

echo Choose MSI Afterburner V/F curve for RTX 4080 Laptop (8BAD):
echo   [1] 225W Uncapped (+237 below 1.020V, +252 uncapped 1.020-1.110V, +347 Mem)
echo   [2] 200W Flat-Capped (+237 Core flat @ 2745 MHz / 1.020V, +347 Mem)
echo.
choice /C 12 /M "Select profile"
if errorlevel 2 set "SRC=%CFGDIR%\VEN_10DE_200W_capped_1.020V.cfg"
if errorlevel 1 if not errorlevel 2 set "SRC=%CFGDIR%\VEN_10DE_225W_uncapped.cfg"
if not defined SRC exit /b 1

if not exist "%BAKDIR%" mkdir "%BAKDIR%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ab = @('C:\Program Files (x86)\MSI Afterburner','C:\Program Files\MSI Afterburner') | Where-Object { Test-Path (Join-Path $_ 'MSIAfterburner.exe') } | Select-Object -First 1; " ^
    "if (-not $ab) { Write-Host '[!] MSI Afterburner not found in standard Program Files folders.' -ForegroundColor Red; exit 1 }; " ^
    "$profDir = Join-Path $ab 'Profiles'; " ^
    "$targetCfg = Get-ChildItem $profDir -Filter 'VEN_10DE&DEV_27E0*.cfg' -ErrorAction SilentlyContinue | Select-Object -First 1; " ^
    "if (-not $targetCfg) { $dest = Join-Path $profDir 'VEN_10DE&DEV_27E0&SUBSYS_8BAD103C&REV_A1&BUS_1&DEV_0&FN_0.cfg' } else { $dest = $targetCfg.FullName }; " ^
    "Stop-Process -Name 'MSIAfterburner' -Force -ErrorAction SilentlyContinue; " ^
    "Start-Sleep -Seconds 2; " ^
    "if (Test-Path $dest) { Copy-Item $dest '%BAKDIR%\afterburner_backup.cfg' -Force; Write-Host ('Backed up existing curve to backups\afterburner_backup.cfg') -ForegroundColor Gray }; " ^
    "Copy-Item '%SRC%' $dest -Force; " ^
    "Write-Host ('Installed V/F curve -> ' + $dest) -ForegroundColor Green; " ^
    "Start-Process -FilePath (Join-Path $ab 'MSIAfterburner.exe') -ArgumentList '-profile1'; " ^
    "Start-Sleep -Seconds 3"

echo.
nvidia-smi --query-gpu=name,power.draw,enforced.power.limit,power.max_limit,clocks.gr,clocks.mem --format=csv
echo.
pause

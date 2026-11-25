@echo off
title Step 2 - Apply RTX 4080 Laptop TGP Unlock (Default 225 W)
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '%*'"
    exit /b
)

set "ROOT=%~dp0.."
set "NVPWR=%ROOT%\nvpwr"
set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=225"

if not exist "%NVPWR%\NvpwrCtl.exe" (
    echo [!] Missing %NVPWR%\NvpwrCtl.exe
    echo Extract NvpwrControl into nvpwr\ first.
    pause
    exit /b 1
)

echo =====================================================================
echo   Step 2: Load Nvpwr.sys and Set RTX 4080 Laptop to %TARGET% W
echo =====================================================================
echo.

powershell -NoProfile -Command ^
    "$opts = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control').SystemStartOptions; " ^
    "Write-Host ('Boot options: ' + $opts) -ForegroundColor Gray; " ^
    "if ($opts -notmatch 'TESTSIGNING') { Write-Host '[!] WARNING: TESTSIGNING is not active! Run Step 1, disable Secure Boot in BIOS, and reboot.' -ForegroundColor Red; exit 1 }"
if %errorlevel% neq 0 (
    echo.
    pause
    exit /b 1
)

echo [1/4] Registering and starting Nvpwr kernel service...
sc.exe query Nvpwr >nul 2>&1
if %errorlevel% neq 0 (
    sc.exe create Nvpwr type= kernel start= demand binPath= "%NVPWR%\Nvpwr.sys" DisplayName= "Nvpwr GPU Power Control"
) else (
    sc.exe config Nvpwr type= kernel start= demand binPath= "%NVPWR%\Nvpwr.sys"
)
sc.exe start Nvpwr >nul 2>&1

echo.
echo [2/4] Dipping briefly to Power saver so NVPCF reaches 175.0 W STOCK_BASELINE, then applying %TARGET% W...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ctl = '%NVPWR%\NvpwrCtl.exe'; " ^
    "$active = ((powercfg /getactivescheme) | Select-String '([0-9a-f-]{36})').Matches.Groups[1].Value; " ^
    "$pwrSaver = '162e1a7b-6914-4ca1-b348-634f73e08a53'; " ^
    "try { " ^
    "    powercfg /setactive $pwrSaver; " ^
    "    for ($i = 0; $i -lt 32; $i++) { " ^
    "        Start-Sleep -Milliseconds 250; " ^
    "        $txt = (& $ctl status) -join \"`n\"; " ^
    "        if ($txt -match 'State\s*:\s*(STOCK_BASELINE|APPLIED)') { break } " ^
    "    } " ^
    "    & $ctl set 4080 %TARGET%; " ^
    "} finally { " ^
    "    if ($active) { powercfg /setactive $active } " ^
    "}"

echo %TARGET%>"%ROOT%\saved_target.txt"

echo.
echo [3/4] Live NvpwrCtl status:
"%NVPWR%\NvpwrCtl.exe" status

echo.
echo [4/4] Live nvidia-smi verification:
nvidia-smi --query-gpu=name,driver_version,temperature.gpu,power.draw,power.default_limit,power.max_limit,enforced.power.limit --format=csv

echo.
echo =====================================================================
echo   %TARGET% W applied and saved to saved_target.txt!
echo =====================================================================
echo.
pause

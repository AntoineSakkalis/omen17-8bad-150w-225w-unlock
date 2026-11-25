@echo off
title Step 3 - Restore Stock 175W and Disable Test Mode
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "ROOT=%~dp0.."
set "NVPWR=%ROOT%\nvpwr"

echo =====================================================================
echo   Restore Stock 175 W OEM Limit and Disable Windows Test Mode
echo =====================================================================
echo.

echo [1/3] Restoring stock OEM power baseline via NvpwrCtl...
if exist "%NVPWR%\NvpwrCtl.exe" (
    "%NVPWR%\NvpwrCtl.exe" restore
)
echo STOCK>"%ROOT%\saved_target.txt"

echo.
echo [2/3] Stopping and removing Nvpwr kernel service...
sc.exe stop Nvpwr >nul 2>&1
sc.exe delete Nvpwr >nul 2>&1

echo.
echo [3/3] Disabling Windows Test-Signing Mode (bcdedit /set testsigning off)...
bcdedit /set testsigning off

echo.
echo =====================================================================
echo   Restored to stock 175 W! Reboot once to exit Test Mode so all
echo   kernel anti-cheat games (FACEIT CS2, EA, Vanguard) work normally.
echo =====================================================================
echo.
pause

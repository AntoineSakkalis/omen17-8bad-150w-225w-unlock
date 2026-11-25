@echo off
title Step 1 - Trust Nvpwr.cer and Enable Windows Test Mode (Then Reboot)
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "NVPWR=%~dp0..\nvpwr"

if not exist "%NVPWR%\Nvpwr.cer" (
    echo [!] Missing %NVPWR%\Nvpwr.cer
    echo Download NvpwrControl from https://github.com/timmyy123/nvidia-power-control
    echo and extract NvpwrControl.exe, NvpwrCtl.exe, Nvpwr.sys, Nvpwr.cer into nvpwr\
    pause
    exit /b 1
)

echo =====================================================================
echo   Step 1: Trust Nvpwr.cer and Enable Windows Test-Signing Mode
echo =====================================================================
echo.

echo [1/4] Suspending BitLocker for 1 reboot if active...
powershell -NoProfile -Command "Suspend-BitLocker -MountPoint 'C:' -RebootCount 1 -ErrorAction SilentlyContinue | Out-Null"

echo [2/4] Installing Nvpwr.cer into Trusted Root and Trusted Publishers...
certutil -addstore -f "Root" "%NVPWR%\Nvpwr.cer"
certutil -addstore -f "TrustedPublisher" "%NVPWR%\Nvpwr.cer"

echo.
echo [3/4] Checking Authenticode signature on Nvpwr.sys...
powershell -NoProfile -Command "$s = Get-AuthenticodeSignature '%NVPWR%\Nvpwr.sys'; Write-Host ('Signature Status: ' + $s.Status + ' (' + $s.StatusMessage + ')') -ForegroundColor Cyan"

echo.
echo [4/4] Enabling Windows Test-Signing Mode (bcdedit /set testsigning on)...
bcdedit /set testsigning on

echo.
echo =====================================================================
echo   DONE! Ensure Secure Boot is DISABLED in BIOS, then REBOOT once
echo   and run: 2-Apply-GPU-TGP-After-Reboot.bat
echo =====================================================================
echo.
pause

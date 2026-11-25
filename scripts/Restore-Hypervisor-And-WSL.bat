@echo off
title Restore Hyper-V and WSL2
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-Hypervisor-And-WSL.ps1"
echo.
choice /C YN /M "Reboot now to restore Hyper-V and WSL2"
if errorlevel 2 (
    pause
    exit /b 0
)
shutdown /r /t 5 /c "Rebooting to restore Hyper-V and WSL2"

@echo off
title Apply i7-13700HX Core 4 & 6 OC + Disable VBS/Hyper-V
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-CPU-OC-And-Disable-VBS.ps1" -FavoredCoreRatio 51

echo.
choice /C YN /M "Reboot now to unload Hyper-V/VBS and activate the unlocked OC"
if errorlevel 2 (
    echo Reboot skipped. Restart Windows manually so VBS/Hyper-V unloads!
    pause
    exit /b 0
)
shutdown /r /t 5 /c "Rebooting to disable VBS/Hyper-V and activate ThrottleStop Core 4 & 6 OC"

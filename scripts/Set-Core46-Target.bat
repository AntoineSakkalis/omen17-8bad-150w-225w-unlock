@echo off
title Switch Core 4 & Core 6 Max Ratio (50x / 51x / 52x)
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Choose favored P-core target ratio (other P-cores stay at 50x):
echo   [1] 51x (5.1 GHz, +0.1 GHz OC)
echo   [2] 52x (5.2 GHz, +0.2 GHz OC)
echo   [0] 50x (5.0 GHz, Stock)
echo.
choice /C 120 /M "Select option"
if errorlevel 3 set TARGET=50
if errorlevel 2 if not errorlevel 3 set TARGET=52
if errorlevel 1 if not errorlevel 2 set TARGET=51
if not defined TARGET exit /b 1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-Core46-Target.ps1" -FavoredCoreRatio %TARGET%
echo.
pause

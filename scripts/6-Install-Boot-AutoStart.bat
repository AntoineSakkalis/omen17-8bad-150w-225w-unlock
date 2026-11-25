@echo off
title Install Boot AutoStart Task (150W CPU + 225W GPU + OmenMon + ThrottleStop)
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "SCRIPT=%~dp0AutoStart-MaxPerf.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$script = '%SCRIPT%'; " ^
    "$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument \"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `\"$script`\" -BootDelay\"; " ^
    "$trigger = New-ScheduledTaskTrigger -AtLogOn; " ^
    "$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest; " ^
    "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5); " ^
    "Register-ScheduledTask -TaskName 'Omen17 MaxPerf AutoUnlock' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null; " ^
    "Write-Host '[OK] Registered logon Scheduled Task: Omen17 MaxPerf AutoUnlock' -ForegroundColor Green; " ^
    "$tsTask = Get-ScheduledTask -TaskName 'ThrottleStop Startup' -ErrorAction SilentlyContinue; " ^
    "if ($tsTask) { " ^
    "  $s = $tsTask.Settings; $s.DisallowStartIfOnBatteries = $false; $s.StopIfGoingOnBatteries = $false; $s.ExecutionTimeLimit = 'PT0S'; " ^
    "  Set-ScheduledTask -TaskName 'ThrottleStop Startup' -Settings $s | Out-Null; " ^
    "  Write-Host '[OK] Removed 72h limit and battery restrictions on ThrottleStop Startup task.' -ForegroundColor Green " ^
    "}; " ^
    "Write-Host 'Running AutoStart-MaxPerf.ps1 now...' -ForegroundColor Yellow; " ^
    "& $script"

echo.
pause

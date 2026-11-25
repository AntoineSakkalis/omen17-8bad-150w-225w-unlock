#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'

Write-Host "Restoring Windows Hypervisor / Hyper-V / WSL2..." -ForegroundColor Cyan
& bcdedit.exe /set hypervisorlaunchtype auto
& bcdedit.exe /deletevalue vsmlaunchtype 2>$null
& bcdedit.exe /deletevalue isolatedcontext 2>$null

Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity','RequirePlatformSecurityFeatures','HypervisorEnforcedCodeIntegrity','LsaCfgFlags' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity','RequirePlatformSecurityFeatures','Locked' -ErrorAction SilentlyContinue

foreach ($feat in @('VirtualMachinePlatform', 'HypervisorPlatform', 'Microsoft-Hyper-V-All')) {
    & dism.exe /online /Enable-Feature /FeatureName:$feat /All /NoRestart | Out-Host
}
Set-Service -Name 'vmms' -StartupType Automatic -ErrorAction SilentlyContinue
Set-Service -Name 'vmcompute' -StartupType Manual -ErrorAction SilentlyContinue
Set-Service -Name 'HvHost' -StartupType Manual -ErrorAction SilentlyContinue

Write-Host "Done! Reboot to re-enable Hyper-V and WSL2." -ForegroundColor Green

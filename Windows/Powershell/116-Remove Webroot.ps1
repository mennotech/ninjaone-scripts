# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Remove Webroot
# ==============================================================================
#
# Description:
#   No description provided
#
# Metadata:
#   - NinjaOne Script ID: 116
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2025-12-24
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-12-24 19:38:28
#   - Active: True
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
# Removes Webroot SecureAnywhere by force
# Run the script once in Safe Mode, then reboot

# Webroot SecureAnywhere registry keys
$RegKeys = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\WRUNINST",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\WRUNINST",
    "HKLM:\SOFTWARE\WOW6432Node\WRData",
    "HKLM:\SOFTWARE\WOW6432Node\WRCore",
    "HKLM:\SOFTWARE\WOW6432Node\WRMIDData",
    "HKLM:\SOFTWARE\WOW6432Node\webroot",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WRUNINST",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WRUNINST",
    "HKLM:\SOFTWARE\WRData",
    "HKLM:\SOFTWARE\WRMIDData",
    "HKLM:\SOFTWARE\WRCore",
    "HKLM:\SOFTWARE\webroot",
    "HKLM:\SYSTEM\ControlSet001\services\WRSVC",
    "HKLM:\SYSTEM\ControlSet001\services\WRkrn",
    "HKLM:\SYSTEM\ControlSet001\services\WRBoot",
    "HKLM:\SYSTEM\ControlSet001\services\WRCore",
    "HKLM:\SYSTEM\ControlSet001\services\WRCoreService",
    "HKLM:\SYSTEM\ControlSet001\services\wrUrlFlt",
    "HKLM:\SYSTEM\ControlSet002\services\WRSVC",
    "HKLM:\SYSTEM\ControlSet002\services\WRkrn",
    "HKLM:\SYSTEM\ControlSet002\services\WRBoot",
    "HKLM:\SYSTEM\ControlSet002\services\WRCore",
    "HKLM:\SYSTEM\ControlSet002\services\WRCoreService",
    "HKLM:\SYSTEM\ControlSet002\services\wrUrlFlt",
    "HKLM:\SYSTEM\CurrentControlSet\services\WRSVC",
    "HKLM:\SYSTEM\CurrentControlSet\services\WRkrn",
    "HKLM:\SYSTEM\CurrentControlSet\services\WRBoot",
    "HKLM:\SYSTEM\CurrentControlSet\services\WRCore",
    "HKLM:\SYSTEM\CurrentControlSet\services\WRCoreService",
    "HKLM:\SYSTEM\CurrentControlSet\services\wrUrlFlt",
    'HKCR\Installer\Products\2C91C1CFE37069649AD21509082D341F\SourceList',
    'HKCR\Installer\Products\2C91C1CFE37069649AD21509082D341F\SourceList\Net',
    'HKCU\Control Panel\NotifyIconSettings\13912443615532443305',
    'HKLM\SOFTWARE\Classes\Installer\Products\2C91C1CFE37069649AD21509082D341F\SourceList',
    'HKLM\SOFTWARE\Classes\Installer\Products\2C91C1CFE37069649AD21509082D341F\SourceList\Net',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\AutorunsDisabled',
    'HKLM\SYSTEM\ControlSet001\Services\EventLog\Application\Webroot-WRLog',
    'HKLM\SYSTEM\ControlSet001\Services\WinSock2\Parameters\AppId_Catalog\2E4983EB',
    'HKLM\SYSTEM\ControlSet001\Services\WRCore',
    'HKLM\SYSTEM\ControlSet001\Services\WRCoreService',
    'HKLM\SYSTEM\ControlSet001\Services\WRSkyClient',
    'HKLM\SYSTEM\ControlSet001\Services\WRSVC',
    'HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Application\Webroot-WRLog',
    'HKLM\SYSTEM\CurrentControlSet\Services\WinSock2\Parameters\AppId_Catalog\2E4983EB',
    'HKLM\SYSTEM\CurrentControlSet\Services\WRCore',
    'HKLM\SYSTEM\CurrentControlSet\Services\WRCoreService',
    'HKLM\SYSTEM\CurrentControlSet\Services\WRSkyClient',
    'HKLM\SYSTEM\CurrentControlSet\Services\WRSVC',
    'HKU\S-1-5-21-2943901566-3547865535-3987560582-1004\Control Panel\NotifyIconSettings\13912443615532443305'
)

# Startup locations
$RegStartupPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
)

# Webroot folders
$Folders = @(
    "$Env:ProgramData\WRData",
    "$Env:ProgramData\WRCore",
    "$Env:ProgramFiles\Webroot",
    "$Env:ProgramFiles(x86)\Webroot",
    "$Env:ProgramData\Microsoft\Windows\Start Menu\Programs\Webroot SecureAnywhere",
    "$Env:ProgramData\Microsoft\Windows\Start Menu\Programs\OpenText™ Core Endpoint Protection",
    "$Env:ProgramFiles\Common Files\Webroot"
)

# Known service names
$Services = @{
    "WRSVC"         = "Webroot SecureAnywhere";
    "WRCoreService" = "Webroot Core Service";
    "WRSkyClient"   = "Webroot Sky Client"
}

# Known uninstall keys
$UninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WRUNINST",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\WRUNINST"
)

# Attempt uninstall if WRSA.exe found
$WrsaPaths = @(
    "${Env:ProgramFiles(x86)}\Webroot\WRSA.exe",
    "${Env:ProgramFiles}\Webroot\WRSA.exe"
)

foreach ($Wrsa in $WrsaPaths) {
    if (Test-Path $Wrsa) {
        Write-Output "Uninstalling via $Wrsa"
        Start-Process -FilePath $Wrsa -ArgumentList "-uninstall" -Wait -ErrorAction SilentlyContinue
    }
}

# Stop and delete services
foreach ($ServiceName in $Services.Keys) {
    $Service = Get-WmiObject -Class Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
    if ($null -ne $Service) {
        Write-Output "Stopping service: $ServiceName"
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Write-Output "Removing service: $ServiceName"
        $Service.Delete() | Out-Null
    }
}

# Kill WRSA.exe process
Write-Output "Killing WRSA process (if running)"
Stop-Process -Name "WRSA" -Force -ErrorAction SilentlyContinue

# Remove registry keys
foreach ($RegKey in $RegKeys) {
    if (Test-Path $RegKey) {
        Write-Output "Removing registry key: $RegKey"
        Remove-Item -Path $RegKey -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# Remove startup entries
foreach ($RegStartupPath in $RegStartupPaths) {
    $StartupEntry = Get-ItemProperty -Path $RegStartupPath -ErrorAction SilentlyContinue
    if ($null -ne $StartupEntry -and $StartupEntry.PSObject.Properties.Name -contains "WRSVC") {
        Write-Output "Removing WRSVC from startup: $RegStartupPath"
        Remove-ItemProperty -Path $RegStartupPath -Name "WRSVC" -ErrorAction SilentlyContinue
    }
}

# Remove folders
foreach ($Folder in $Folders) {
    $Expanded = [Environment]::ExpandEnvironmentVariables($Folder)
    if (Test-Path $Expanded) {
        Write-Output "Removing folder: $Expanded"
        Remove-Item -Path $Expanded -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Remove known Add/Remove Program keys
foreach ($Key in $UninstallKeys) {
    if (Test-Path $Key) {
        Write-Output "Removing uninstall key: $Key"
        Remove-Item -Path $Key -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Remove any uninstall entries that mention Webroot
$UninstallRootPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($RootPath in $UninstallRootPaths) {
    Get-ChildItem -Path $RootPath -ErrorAction SilentlyContinue | ForEach-Object {
        $Props = Get-ItemProperty -Path $_.PsPath -ErrorAction SilentlyContinue
        if ($null -ne $Props.DisplayName -and $Props.DisplayName -like "*Webroot*") {
            Write-Output "Removing detected uninstall key: $($_.PsPath) [$($Props.DisplayName)]"
            Remove-Item -Path $_.PsPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
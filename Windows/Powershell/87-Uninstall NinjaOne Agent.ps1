# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Uninstall NinjaOne Agent
# ==============================================================================
#
# Description:
#   No description provided
#
# Metadata:
#   - NinjaOne Script ID: 87
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2025-04-28
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-04-28 21:03:48
#   - Active: True
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
# INSTRUCTIONS:
# 1. Open NinjaOne GUI: https://ca.ninjarmm.com
# 2. Navigate to: Administration → Library → Automation → Scripts
# 3. Find and open: "Uninstall NinjaOne Agent"
# 4. Copy the entire script content
# 5. Paste below this header (replace the placeholder comment)
# 6. Save and commit to Git
# ==============================================================================
#Get current user context
$CurrentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
#Check user that is running the script is a member of Administrator Group
if (!($CurrentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))) {
  #UAC Prompt will occur for the user to input Administrator credentials and relaunch the powershell session
  Write-Output 'This script must be ran with administrative privileges'
  Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; Exit
}

$Now = Get-Date -Format 'dd-MM-yyyy_HHmmss'
$LogPath = "$env:windir\temp\NinjaRemoval_$Now.txt"
Start-Transcript -Path $LogPath -Force
$ErrorActionPreference = 'SilentlyContinue'
function Uninstall-NinjaMSI {
  $Arguments = @(
    "/x$($UninstallString)"
    '/quiet'
    '/L*V'
    'C:\windows\temp\NinjaRMMAgent_uninstall.log'
    "WRAPPED_ARGUMENTS=`"--mode unattended`""
  )

  Start-Process "$NinjaInstallLocation\NinjaRMMAgent.exe" -ArgumentList "-disableUninstallPrevention NOUI"
  Start-Sleep 10
  Start-Process "msiexec.exe" -ArgumentList $Arguments -Wait -NoNewWindow
  Write-Output 'Finished running uninstaller. Continuing to clean up...'
  Start-Sleep 30
}

$NinjaRegPath = 'HKLM:\SOFTWARE\WOW6432Node\NinjaRMM LLC\NinjaRMMAgent'
$NinjaDataDirectory = "$($env:ProgramData)\NinjaRMMAgent"
$UninstallRegPath = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'

Write-Output 'Beginning NinjaRMM Agent removal...'

if (!([System.Environment]::Is64BitOperatingSystem)) {
  $NinjaRegPath = 'HKLM:\SOFTWARE\NinjaRMM LLC\NinjaRMMAgent'
  $UninstallRegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
}

$NinjaInstallLocation = (Get-ItemPropertyValue $NinjaRegPath -Name Location).Replace('/', '\') 

if (!(Test-Path "$($NinjaInstallLocation)\NinjaRMMAgent.exe")) {
  $NinjaServicePath = ((Get-Service | Where-Object { $_.Name -eq 'NinjaRMMAgent' }).BinaryPathName).Trim('"')
  if (!(Test-Path $NinjaServicePath)) {
    Write-Output 'Unable to locate Ninja installation path. Continuing with cleanup...'
  }
  else {
    $NinjaInstallLocation = $NinjaServicePath | Split-Path
  }
}

$UninstallString = (Get-ItemProperty $UninstallRegPath | Where-Object { ($_.DisplayName -eq 'NinjaRMMAgent') -and ($_.UninstallString -match 'msiexec') }).UninstallString

if (!($UninstallString)) {
  Write-Output 'Unable to to determine uninstall string. Continuing with cleanup...' 
}
else {
  $UninstallString = $UninstallString.Split('X')[1]
  Uninstall-NinjaMSI
}

$NinjaServices = @('NinjaRMMAgent', 'nmsmanager', 'lockhart')
$Processes = @("NinjaRMMAgent", "NinjaRMMAgentPatcher", "njbar", "NinjaRMMProxyProcess64")


foreach ($Process in $Processes) {
  Get-Process $Process | Stop-Process -Force 
}

foreach ($NS in $NinjaServices) {
  if (($NS -eq 'lockhart') -and !(Test-Path "$NinjaInstallLocation\lockhart\bin\lockhart.exe")) {
    continue
  }
  if (Get-Service $NS) {
    & sc.exe DELETE $NS
    Start-Sleep 2
    if (Get-Service $NS) {
      Write-Output "Failed to remove service: $($NS). Continuing with removal attempt..."
    }
  }
}

if (Test-Path $NinjaInstallLocation) {
  Remove-Item $NinjaInstallLocation -Recurse -Force
  if (Test-Path $NinjaInstallLocation) {
    Write-Output 'Failed to remove Ninja Installation Directory:'
    Write-Output "$NinjaInstallLocation"
    Write-Output 'Continuing with removal attempt...'
  } 
}

if (Test-Path $NinjaDataDirectory) {
  Remove-Item $NinjaDataDirectory -Recurse -Force
  if (Test-Path $NinjaDataDirectory) {
    Write-Output 'Failed to remove Ninja Data Directory:'
    Write-Output "$NinjaDataDirectory"
    Write-Output 'Continuing with removal attempt...'
  }
}

$MSIWrapperReg = 'HKLM:\SOFTWARE\WOW6432Node\EXEMSI.COM\MSI Wrapper\Installed'
$ProductInstallerReg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products'
$HKCRInstallerReg = 'Registry::\HKEY_CLASSES_ROOT\Installer\Products'

$RegKeysToRemove = [System.Collections.Generic.List[object]]::New()

(Get-ItemProperty $UninstallRegPath | Where-Object { $_.DisplayName -eq 'NinjaRMMAgent' }).PSPath | ForEach-Object { $RegKeysToRemove.Add($_) }
(Get-ItemProperty $ProductInstallerReg | Where-Object { $_.ProductName -eq 'NinjaRMMAgent' }).PSPath | ForEach-Object { $RegKeysToRemove.Add($_) }
(Get-ChildItem $MSIWrapperReg | Where-Object { $_.Name -match 'NinjaRMMAgent' }).PSPAth | ForEach-Object { $RegKeysToRemove.Add($_) }
Get-ChildItem $HKCRInstallerReg | ForEach-Object { if ((Get-ItemPropertyValue $_.PSPath -Name 'ProductName') -eq 'NinjaRMMAgent') { $RegKeysToRemove.Add($_.PSPath) } }

$ProductInstallerKeys = Get-ChildItem $ProductInstallerReg | Select-Object *
foreach ($Key in $ProductInstallerKeys) {
  $KeyName = $($Key.Name).Replace('HKEY_LOCAL_MACHINE', 'HKLM:') + "\InstallProperties"
  if (Get-ItemProperty $KeyName | Where-Object { $_.DisplayName -eq 'NinjaRMMAgent' }) {
    $RegKeysToRemove.Add($Key.PSPath)
  }
}

Write-Output 'Removing registry items if found...'
foreach ($RegKey in $RegKeysToRemove) {
  if (!([string]::IsNullOrEmpty($RegKey))) {
    Write-Output "Removing: $($RegKey)"
    Remove-Item $RegKey -Recurse -Force
  }
}

if (Test-Path $NinjaRegPath) {
  Get-Item ($NinjaRegPath | Split-Path) | Remove-Item -Recurse -Force
  Write-Output "Removing: $($NinjaRegPath)"
}

foreach ($RegKey in $RegKeysToRemove) {
  if (!([string]::IsNullOrEmpty($RegKey))) {
    if (Test-Path $RegKey) {
      Write-Output 'Failed to remove the following registry key:'
      Write-Output "$($RegKey)"
    }
  }   
}

if (Test-Path $NinjaRegPath) {
  Write-Output "$NinjaRegPath"
}

#Checks for rogue reg entry from older installations where ProductName was missing
#Filters out a Windows Common GUID that doesn't have a ProductName
$Child = Get-ChildItem 'HKLM:\Software\Classes\Installer\Products'
$MissingPNs = [System.Collections.Generic.List[object]]::New()

foreach ($C in $Child) {
  if ($C.Name -match '99E80CA9B0328e74791254777B1F42AE') {
    continue
  }
  try {
    Get-ItemPropertyValue $C.PSPath -Name 'ProductName' -ErrorAction Stop | Out-Null
  }
  catch {
    $MissingPNs.Add($($C.Name))
  } 
}

if ($MissingPNs) {
  Write-Output 'Some registry keys are missing the Product Name.'
  Write-Output 'This could be an indicator of a corrupt Ninja install key.'
  Write-Output 'If you are still unable to install the Ninja Agent after running this script...'
  Write-Output 'Please make a backup of the following keys before removing them from the registry:'
  Write-Output ( $MissingPNs | Out-String )
}

##Begin Ninja Remote Removal##
$NR = 'ncstreamer'

if (Get-Process $NR -ErrorAction SilentlyContinue) {
   Write-Output 'Stopping Ninja Remote process...'
    try {
        Get-Process $NR | Stop-Process -Force
    }
    catch {
       Write-Output 'Unable to stop the Ninja Remote process...'
       Write-Output "$($_.Exception)"
       Write-Output 'Continuing to Ninja Remote service...'
    }
}

if (Get-Service $NR -ErrorAction SilentlyContinue) {
    try {
        Stop-Service $NR -Force
    }
    catch {
       Write-Output 'Unable to stop the Ninja Remote service...'
       Write-Output "$($_.Exception)"
       Write-Output 'Attempting to remove service...'
    }

    & sc.exe DELETE $NR
    Start-Sleep 5
    if (Get-Service $NR -ErrorAction SilentlyContinue) {
       Write-Output 'Failed to remove Ninja Remote service. Continuing with remaining removal steps...'
    }
}

$NRDriver = 'nrvirtualdisplay.inf'
$DriverCheck = pnputil /enum-drivers | Where-Object { $_ -match "$NRDriver" }
if ($DriverCheck) {
   Write-Output 'Ninja Remote Virtual Driver found. Removing...'
    $DriverBreakdown = pnputil /enum-drivers | Where-Object { $_ -ne 'Microsoft PnP Utility' }

    $DriversArray = [System.Collections.Generic.List[object]]::New()
    $CurrentDriver = @{}
    
    foreach ($Line in $DriverBreakdown) {
        if ($Line -ne "") {
            $ObjectName = $Line.Split(':').Trim()[0]
            $ObjectValue = $Line.Split(':').Trim()[1]
            $CurrentDriver[$ObjectName] = $ObjectValue
        }
        else {
            if ($CurrentDriver.Count -gt 0) {
                $DriversArray.Add([PSCustomObject]$CurrentDriver)
                $CurrentDriver = @{}
            }
        }
    }

    $DriverToRemove = ($DriversArray | Where-Object {$_.'Provider Name' -eq 'NinjaOne'}).'Published Name'
    pnputil /delete-driver "$DriverToRemove" /force
}

$NRDirectory = "$($env:ProgramFiles)\NinjaRemote"
if (Test-Path $NRDirectory) {
   Write-Output "Removing directory: $NRDirectory"
    Remove-Item $NRDirectory -Recurse -Force
    if (Test-Path $NRDirectory) {
       Write-Output 'Failed to completely remove Ninja Remote directory at:'
       Write-Output "$NRDirectory"
       Write-Output 'Continuing to registry removal...'
    }
}

$NRHKUReg = 'Registry::\HKEY_USERS\S-1-5-18\Software\NinjaRMM LLC'
if (Test-Path $NRHKUReg) {
    Remove-Item $NRHKUReg -Recurse -Force
}

function Remove-NRRegistryItems {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SID
    )
    $NRRunReg = "Registry::\HKEY_USERS\$SID\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    $NRRegLocation = "Registry::\HKEY_USERS\$SID\Software\NinjaRMM LLC"
    if (Test-Path $NRRunReg) {
        $RunRegValues = Get-ItemProperty -Path $NRRunReg
        $PropertyNames = $RunRegValues.PSObject.Properties | Where-Object { $_.Name -match "NinjaRMM|NinjaOne" } 
        foreach ($PName in $PropertyNames) {    
           Write-Output "Removing item..."
           Write-Output "$($PName.Name): $($PName.Value)"
            Remove-ItemProperty $NRRunReg -Name $PName.Name -Force
        }
    }
    if (Test-Path $NRRegLocation) {
       Write-Output "Removing $NRRegLocation..."
        Remove-Item $NRRegLocation -Recurse -Force
    }
   Write-Output 'Registry removal completed.'
}

$AllProfiles = Get-CimInstance Win32_UserProfile | Select-Object LocalPath, SID, Loaded, Special | 
Where-Object { $_.SID -like "S-1-5-21-*" }
$Mounted = $AllProfiles | Where-Object { $_.Loaded -eq $true }
$Unmounted = $AllProfiles | Where-Object { $_.Loaded -eq $false }

$Mounted | Foreach-Object {
   Write-Output "Removing registry items for $LocalPath"
    Remove-NRRegistryItems -SID "$($_.SID)"
}

$Unmounted | ForEach-Object {
    $Hive = "$($_.LocalPath)\NTUSER.DAT"
    if (Test-Path $Hive) {      
        Write-Output "Loading hive and removing Ninja Remote registry items for $($_.LocalPath)..."

        REG LOAD HKU\$($_.SID) $Hive 2>&1>$null

        Remove-NRRegistryItems -SID "$($_.SID)"
        
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
          
        REG UNLOAD HKU\$($_.SID) 2>&1>$null
    } 
}

$NRPrinter = Get-Printer | Where-Object { $_.Name -eq 'NinjaRemote' }

if ($NRPrinter) {
   Write-Output 'Removing Ninja Remote printer...'
    Remove-Printer -InputObject $NRPrinter
}

$NRPrintDriverPath = "$env:SystemDrive\Users\Public\Documents\NrSpool\NrPdfPrint"
if (Test-Path $NRPrintDriverPath) {
   Write-Output 'Removing Ninja Remote printer driver...'
    Remove-Item $NRPrintDriverPath -Force
}

Write-Host 'Removal of Ninja Remote complete.'
##End Ninja Remote Removal##

Write-Output 'Removal script completed. Please review if any errors displayed.'
Stop-Transcript
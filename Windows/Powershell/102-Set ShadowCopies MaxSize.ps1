# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Set ShadowCopies MaxSize
# ==============================================================================
#
# Description:
#   Changes the maximum size used for Windows Shadow Copies storage
#
# Metadata:
#   - NinjaOne Script ID: 102
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2025-06-12
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-06-18 22:07:49
#   - Active: True
# Script Variables (NinjaOne):
#   - size (INTEGER, Required): Max Shadow Copies Storage as percentage of 100
#     Default: 10
#   - drive (TEXT, Optional): The drive letter
#     Default: C
#
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
<#
.SYNOPSIS
    This script sets the maximum size for Windows Shadow Copies on a specified drive.
.DESCRIPTION
    The script allows you to set the maximum size for Shadow Copies on a specified drive (default is C:).
    It checks the current configuration, attempts to update the maximum size, and displays the new configuration.
    If the update fails, it provides an error message.    

    The script takes the folloing Parmeters:
      -Size (REQUIRED)   An integer as used as the total percentage that Windows can allocate to Shadow Copies
      -Drive             A single letter for the drive to configure, default value is "C"

.EXAMPLE
    -Size 5

Current configuration:
  Used Shadow Copy Storage space: 4.68 GB (1%)
  Allocated Shadow Copy Storage space: 5.05 GB (2%)
  Maximum Shadow Copy Storage space: 23.7 GB (10%)
Attempting to update max size to 5%
Update failed:
  Error: The shadow copy provider had an error. Please see the system and
  application event logs for more information.



    -Size 10 -Drive C

Current configuration:
  Used Shadow Copy Storage space: 4.68 GB (1%)
  Allocated Shadow Copy Storage space: 5.05 GB (2%)
  Maximum Shadow Copy Storage space: 23.7 GB (10%)
Attempting to update max size to 5%
Update failed:
  Error: The shadow copy provider had an error. Please see the system and
  application event logs for more information.


.OUTPUTS
    Displays the current and new configuration of Shadow Copies on the specified drive.
    If the update fails, an error message is displayed.

.NOTES
    2025-06-18: Initial version of the script.

.LINK
    https://github.com/mennotech/rmm-scripts/blob/main/powershell/Set-ShadowCopies-MaxSize.ps1

.LICENSE
    This script is released under the MIT License.
#>


Param(
    [int] $Size = 0,
    [string] $Drive = "C"
)

# Replace parameters with dynamic script variables.
if ($env:Size -and $env:Size -notlike "null") { $Size = $env:Size}
if ($env:Drive -and $env:Drive -notlike "null") { $Drive = $env:Drive }

if ($Size -eq 0) {
  Write-Host "Usage: $0 -Size [int] -Drive [drive letter]"
  Exit 1
}

if ($Size -lt 2) {
    Write-Host "Minimum Size is 2%, exiting (Got $Size)"
    Exit 10
}

if ($Size -gt 50) {
    Write-Host "Maximum Size is 50%, exiting"
    Exit 10
}

if ((Get-PSDrive -Name $Drive -ErrorAction SilentlyContinue).Count -ne 1) {
    Write-Host "Drive $Drive is invalid."
    Exit 11
}


Write-Host "Current configuration:"
$currentconfig = C:\Windows\System32\vssadmin.exe List ShadowStorage /On="$($Drive):"
$currentconfig| Where-Object {$_ -match "Used|Allocated|Maximum"} | % { Write-Host " "($_).trim() }

Write-Host "Attempting to update max size to $($Size)%"
$update = C:\Windows\System32\vssadmin.exe Resize ShadowStorage /For="$($Drive):" /On="$($Drive):" /MaxSize="$($Size)%"

if ($update -match "Successfully resized") {

    Write-Host "New configuration:"
    $newconfig = C:\Windows\System32\vssadmin.exe List ShadowStorage /On="$($Drive):"
    $newconfig | Where-Object {$_ -match "Used|Allocated|Maximum"} | % { Write-Host " "($_).trim() }

} else {
    Write-Host "Update failed:"
    $update | Select-Object -Skip 3 | % { Write-Host " "($_).trim() }
    exit 2
}
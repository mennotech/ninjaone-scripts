# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Block Windows Shell Extensions
# ==============================================================================
#
# Description:
#   This script can be used to prevent specific shell extensions from being loaded by Windows Explorer. Explorer must be restarted for the changes to take effect.
#
# Metadata:
#   - NinjaOne Script ID: 104
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2025-06-18
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-06-18 22:06:46
#   - Active: True
# Script Variables (NinjaOne):
#   - extension (TEXT, Required): The Class ID of an extension or the Exact Name of the extension, you can provide multiple names separated by commas (no quotes)
#   - force (TEXT, Required): Set this value to true and specify a class ID to force blocking an extension by Class ID
#     Default: false
#
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
#Requires -Version 5.1

<#
.SYNOPSIS
    This script can be used to prevent specific shell extensions from being loaded by Windows Explorer.
    Explorer must be restarted for the changes to take effect.
.DESCRIPTION
    This script adds a specified shell extension to the block list in the Windows registry.
    If a class ID is provided, it will be added directly to the block list.
    If a name is provided, it will look up the class ID in the approved list before blocking.
    The script can also force the addition of an extension to the block list even if it is not found in 
    the approved list. However you must specify a class ID to block with the -Force "true".
    
    The approved and blocked extensions are managed in the following registry keys:
    - Approved: `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved`
    - Blocked: `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked`
    
.EXAMPLE
    Block-Windows-Shell-Extensions.ps1 -Extension "{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}" -Force "true"
    This will block the shell extension with the specified class ID, even if it is not found in the approved list.
    
    Block-Windows-Shell-Extensions.ps1 -Extension "Some Extension Name"
    This will look up the class ID for "Some Extension Name" in the approved list and block it.
.OUTPUTS
    Logs the actions taken to the console, including whether the extension was found in the approved list,
    whether it was added to the block list, and any warnings if the extension was not found.
.NOTES
    2025-06-18: Initial version of the script.

.LINK
    https://github.com/mennotech/rmm-scripts/blob/main/powershell/Block-Windows-Shell-Extensions.ps1

.LICENSE
    This script is released under the MIT License.
#>

[CmdletBinding()]
param (
    [string]$Extension = "",    # If a class ID is provided, it will be added to the block list. If a name is specified, it must be found in the approved list.
    [string]$Force = "false"    # Optional flag to force add the extension to the block list, even if it is not found in the approved list, pass in string "true" or "false"#
)

begin {
    if ($env:extension -and $env:extension -notlike "null") { $extension = $env:extension }
    if ($env:force -and $env:force -notlike "null") { $force = $env:force }

    $forceBlock = $force -eq "true" # Convert to boolean
    
    $approvedKey = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved" # The registry key path where the approved extensions are stored.
    $blockKey = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"      # The registry key path where the blocked extensions are stored.

    function Block-ShellExtension {
        param(
            [string]$classId,  # The class ID of the shell extension to block.            
            [string]$Name = "" # Optional name of the shell extension, used for logging purposes.
        )
        
        if (-not ($Extension = Get-ItemProperty -Path $approvedKey -Name $classId -ErrorAction SilentlyContinue)) {
            
            if (-not $forceBlock) { 
                Write-Warning "Class ID '$classId' not found in approved list. Use -Force `"true`" to add it to the block list."
                return
            } else {
                Write-Host "Class ID '$classId' not found in approved list. Adding to block list anyway due to -Force flag."
            }
        } else {
            Write-Host "Found class ID '$classId' in approved list. Proceeding to add to block list."
        }

        # Ensure the block key exists
        if (-not (Test-Path -Path $blockKey)) {
            try {
                New-Item -Path $blockKey -Force | Out-Null
            } catch {
                Write-Warning "Failed to create block key: $_"
                exit 1
            }
        }

        # Check if the class ID already exists in the block list
        if (Get-ItemProperty -Path $blockKey -Name $classId -ErrorAction SilentlyContinue) {
            Write-Warning "Class ID '$classId' is already in the block list."
            return
        }

        # Add the class ID to the block list
        try {
            #Join the name with the current date and time for logging purposes
            if (-not $Name) { $Name = "Unknown Extension"}
            $BlockNote = "$Name - Blocked on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') by Block-Windows-Shell-Extensions.ps1 script"
            New-ItemProperty -Path $blockKey -Name $classId -Value $BlockNote -PropertyType String -Force | Out-Null
        } catch {
            Write-Warning "Failed to create block key: $_"
            exit 1
        }
        
        # Check if the class ID was successfully added to the block list
        if (-not (Get-ItemProperty -Path $blockKey -Name $classId -ErrorAction SilentlyContinue)) {
            Write-Warning "Failed to add class ID '$classId' to the block list."
            exit 1
        } else {
            Write-Host "Class ID '$classId' has been added to the block list with note: '$BlockNote'."
        }
    
    }
}
process {
    # Ensure script is run with administrative privileges
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "This script must be run as an administrator."
        exit 1
    }


    $Extension = $Extension.Trim()

    if (-not $Extension) {
        Write-Warning "No extension provided. Please specify a class ID or name."
        exit 1
    }
    # Determine of the extension is a class ID or a name
    # Class IDs are in the format {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}
    if ($Extension -match "^{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}}$") {
        $classId = $Extension
        Block-ShellExtension -classId $classId
    } else {

        # Check if the approved key exists
        if (-not (Test-Path -Path $approvedKey)) {
            Write-Warning "Approved registry key does not exist: $approvedKey"
            exit 1
        }

        $Extensions = $Extension -split ','

        # Get the allowed extensions from the approved registry key
        $AllowedExtensions = Get-ItemProperty -Path $approvedKey
        
        foreach ($Extension in $Extensions) {
            Write-Host "Processing extension: $Extension"
            $Extension = $Extension.Trim()

            $matchedExtensions = $AllowedExtensions.PSObject.Properties | Where-Object { $_.Value -eq $Extension }

            if ($matchedExtensions.Count -eq 0) {
                Write-Warning "No class ID found for the name '$Extension' in the approved list."
                continue
            } elseif ($matchedExtensions.Count -eq 1) {
                Write-Host "Found class ID for the name '$Extension' in the approved list."
                $classId = $matchedExtensions.Name            
                Block-ShellExtension -classId $classId -Name $Extension
            }            
        }
    }
}

end {

}

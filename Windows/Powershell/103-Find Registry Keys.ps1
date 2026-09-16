# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Find Registry Keys
# ==============================================================================
#
# Description:
#   This script recursively retrieves and displays all registry keys and values from a specified registry path.
#   It can format the output as a registry file if the formatRegFile parameter is set to "true".
#
# Metadata:
#   - NinjaOne Script ID: 103
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2025-06-18
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-06-18 22:07:17
#   - Active: True
# Script Variables (NinjaOne):
#   - regkeypath (TEXT, Required): 
#     Default: HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
#   - depth (INTEGER, Required): The depth of child items to traverse
#     Default: 1
#   - filtervalue (TEXT, Optional): A comma separated list of Registry properties to filter by
#   - formatregfile (TEXT, Required): Enter true or false
#     Default: false
#
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
#Requires -Version 5.1

<#
.SYNOPSIS
    This script retrieves and displays all registry keys and values from a specified registry path.
    
.DESCRIPTION
    The script allows you to specify a registry key path and a depth level to explore subkeys.
    It can also filter the displayed values based on specified property names and format the output as a registry file.
    It can format the output as a registry file if the -formatRegFile parameter is set to "true".
.EXAMPLE
    -regKeyPath "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" -depth 2 -filterValue @("DisplayName","UninstallString") -formatRegFile "true"
    This will search the specified registry key path, display values for DisplayName and UninstallString, and format the output as a registry file.

    -regKeyPath "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer" -depth 1
.OUTPUTS
    Displays the registry keys and values in the console, or formats them as a registry file if specified.    
    If -formatRegFile is set to "true", the output will be formatted as a Windows Registry Editor Version 5.00 file.    
    If -filterValue is specified, only those values will be displayed.    
    If the specified registry key path does not exist, a warning will be displayed.
.NOTES
    2025-06-18: Initial version of the script.
.LINK
    https://github.com/mennotech/rmm-scripts/blob/main/powershell/Find-Registry-Keys.ps1

.LICENSE
    This script is released under the MIT License.
#>

[CmdletBinding()]
param (
    [string]$regKeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    [int]$depth = 2,
    [array]$filterValue = $null, # Optional filter value to display, example: @("DisplayName","UninstallString"),
    [string]$formatRegFile = "false" # Optional flag to format output as a registry file, pass in string "true" or "false"
)

begin {
    if ($env:regKeyPath -and $env:reKeyPath -notlike "null") { $regKeyPath = $env:regKeyPath }
    if ($env:depth -and $env:depth -notlike "null") { $depth = [int]$env:depth }
    if ($env:filterValue -and $env:filterValue -notlike "null") { 
        $filterValue = $env:filterValue -split ',' | ForEach-Object { $_.Trim() } 
    }
    if ($env:formatRegFile -and $env:formatRegFile -notlike "null") { $formatRegFile = [string]$env:formatRegFile }
    $regFormat = $formatRegFile -eq "true" # Convert to boolean
}
process {


function Main{
    try {
        # Ensure the registry key path exists
        if (-Not (Test-Path -Path "Registry::$regKeyPath")) {
            Write-Warning "Registry key does not exist: $regKeyPath"
            exit 1
        }

        Write-Host "Searching registry key: $regKeyPath with depth: $depth"
        Write-Host "----------------------"
        
        if ($regFormat) { 
            Write-Host "Windows Registry Editor Version 5.00"
        }

        $rootKey = Get-Item -Path "Registry::$regKeyPath" -ErrorAction Stop
        Write-Host "`n[$($rootKey)]"

        Get-RegistryKeys -path "Registry::$regKeyPath" -currentDepth 1 -maxDepth $depth
        Write-Host "`n----------------------"

    } catch {
            Write-Warning "An error occurred: $_"
            exit 1
    }
}

# Function to recursively retrieve registry keys
function Get-RegistryKeys {
    param (
        [string]$path,
        [int]$currentDepth,
        [int]$maxDepth
    )

    if ($currentDepth -gt $maxDepth) {
        return
    }

    try {
        
        # Write the current registry key path values
        Write-RegistryValues -path $path
        
        # Get all child keys at the current path
        $keys = Get-ChildItem -Path $path -ErrorAction Stop
        foreach ($key in $keys) {
            Write-Host "`n[$($key)]"
            # Recursively call this function for child values
            Get-RegistryKeys -path $key.PSPath -currentDepth ($currentDepth + 1) -maxDepth $maxDepth
        }
    } catch {
        Write-Warninginging "Error accessing registry key: $path"
    }
}

# Function to write all registry values to output
function Write-RegistryValues {
    param (
        [string]$path
    )

    try {
        $key = Get-Item -Path $path -ErrorAction Stop
        $values = Get-ItemProperty -Path $path -ErrorAction Stop
        foreach ($value in $values.PSObject.Properties) {
            # Skip certain properties that are not relevant for display
            if ($value.Name -in @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')) {
                continue
            }
            # Check if the value is in the filterValue array, if provided
            if ($filterValue -and $value.Name -notin $filterValue) {
                continue
            }
            if ($regFormat) {
                Output-Regformat -key $key -value $value
            } else {
                Write-Host "$($value.Name) = $($value.Value)"
            }
        }
    } catch {
        Write-Warning "Error accessing registry values at: $path"
        Write-Warning "Error details: $_"
    }
}

function Output-Regformat {
param(
    [object]$key,
    [object]$value
)

    
    if ($value.Name -eq "(default)") {
        $propertyName = "@"
    } else {
        $propertyName = $value.Name
    }

    $type = $key.GetValueKind($value.Name)        
    switch($type) {
        "String" { 
            Write-Host "`"$($propertyName)`"=`"$($value.Value)`""
        }
        "ExpandString" { 
            $padded = $value.Value + "`0"
            $binaryValues = [BitConverter]::ToString([System.Text.Encoding]::Unicode.GetBytes($padded)) -replace '-', ','
            Write-Host "`"$($propertyName)`"=hex(2):$($binaryValues)"
        }
        "Binary" { 
            # Convert binary data to hex format                    
            $binaryValues = [BitConverter]::ToString($value.Value) -replace '-', ','                    
            Write-Host "`"$($propertyName)`"=hex:$($binaryValues)"
        }
        "DWord" { 
            #Convert Int to hex format for display                    
            $valueHex = "{0:X8}" -f $value.Value
            Write-Host "`"$($propertyName)`"=dword:$($valueHex)"
        }
        "QWord" { 
            # Convert binary data to hex format
            $binaryValues = [BitConverter]::ToString([BitConverter]::GetBytes($value.Value)) -replace '-', ','
            Write-Host "`"$($propertyName)`"=hex(b):$($binaryValues)"
        }
        "MultiString" { 
            # Join all strings with null, then add a final null terminator
            $joined = ($value.Value -join "`0") + "`0" + "`0"
            #String to binary format
            $binaryValues = [BitConverter]::ToString([System.Text.Encoding]::Unicode.GetBytes($joined)) -replace '-', ','
            Write-Host "`"$($propertyName)`"=hex(7):$($binaryValues)"
        }
        default {                     
            Write-Warning "Unknown value type for property '$($propertyName)' in key '$($key.Name)': $type"
        }
    }
}

Main

}
end {


}

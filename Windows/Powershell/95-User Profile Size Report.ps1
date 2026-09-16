# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: User Profile Size Report
# ==============================================================================
#
# Description:
#   Updates a Custom Field with the total size of all User Profiles. If the Max parameter is specified then it will return an exit code of 1 for any profile being over that Max threshold in GB.
#
# Metadata:
#   - NinjaOne Script ID: 95
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: NinjaOne
#   - Created On: 2025-05-31
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-06-18 22:25:01
#   - Active: True
# Script Variables (NinjaOne):
#   - sizeInGbToAlertOn (DECIMAL, Optional): Generate an alert when the profile size is greater than x GB's.
#   - customFieldNameGb (TEXT, Optional): Name of a decimal customfield to send total size to.
#     Default: TotalUsersProfileSizeGB
#   - customFieldNameDetail (TEXT, Optional): Name of a multiline customfield to send details of each profile size
#     Default: TotalUsersProfileSizeDetail
#
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
#Requires -Version 5.1

<#
.SYNOPSIS
    This script calculates the total size of all User Profiles on a Windows system and updates a custom field with the total size in GB.
    It can also check if any profile exceeds a specified maximum size in GB.
.DESCRIPTION
    This script retrieves all user profiles from the C:\Users directory, calculates their total size, and formats the output.
    It can also check if any profile exceeds a specified maximum size in GB and updates a custom field with the total size in GB.
    The script requires administrative privileges to run.
    The script can be run with the following parameters:
    -Max: Specifies the maximum size in GB for user profiles. If any profile exceeds this size, the script will exit with code 1.
        defaults to 0 if not provided.
    -CustomFieldGB: Specifies the name of the custom field to update with the total size in GB.
        defaults to an empty string if not provided.
    -CustomFieldDetail: Specifies the name of the custom field to update with detailed profile size information.
        defaults to an empty string if not provided.
    

.EXAMPLE
     -Max 60
    Returns and exit code of 1 if any profile is over 60GB
     
     -CustomFieldGB "Something"
    Updates the custom field "Something" with the total size in GB of all user profiles.
    Returns and exit code of 0 if no profile exceeds the specified maximum size.
     
     -CustomFieldDetail "ProfileSizes"
    Updates the custom field "ProfileSizes" with detailed information about the size of each user profile.


.OUTPUTS
    Outputs the total size of all user profiles in GB and detailed information about each profile's size.
    If any profile exceeds the specified maximum size, it outputs an error message and exits with code 1.
.NOTES
    2025-06-18: Initial version of the script.
.LINK
    https://github.com/mennotech/rmm-scripts/blob/main/powershell/User-Profile-Size-Report.ps1

.LICENSE
    This script is released under the MIT License.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [Alias("MaxSize", "Size", "ms", "m", "s")]
    [Double]$Max,
    [Parameter()]
    [Alias("CustomGB", "FieldGB", "cfg" )]
    [String]$CustomFieldGB = "",
    [Parameter()]
    [Alias("CustomDetail", "FieldDetail", "cfd")]
    [String]$CustomFieldDetail = ""
)

begin {
    if ($env:sizeInGbToAlertOn -and $env:sizeInGbToAlertOn -notlike "null") { $Max = $env:sizeInGbToAlertOn }
    if ($env:customFieldNameGB -and $env:customFieldNameGB -notlike "null") { $CustomFieldGB = $env:customFieldNameGB }
    if ($env:customFieldNameDetail -and $env:customFieldNameDetail -notlike "null") { $CustomFieldDetail = $env:customFieldNameDetail }
    function Test-IsElevated {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object System.Security.Principal.WindowsPrincipal($id)
        $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    function Format-FileSize {
        param($Length)
        switch ($Length) {
            { $_ / 1TB -gt 1 } { "$([Math]::Round(($_ / 1TB),2)) TB"; break }
            { $_ / 1GB -gt 1 } { "$([Math]::Round(($_ / 1GB),2)) GB"; break }
            { $_ / 1MB -gt 1 } { "$([Math]::Round(($_ / 1MB),2)) MB"; break }
            { $_ / 1KB -gt 1 } { "$([Math]::Round(($_ / 1KB),2)) KB"; break }
            Default { "$_ Bytes" }
        }
    }
}
process {
    if (-not (Test-IsElevated)) {
        Write-Error -Message "Access Denied. Please run with Administrator privileges."
        exit 1
    }

    $Profiles = Get-ChildItem -Path "C:\Users"
    $ProfileSizes = $Profiles | ForEach-Object {
        [PSCustomObject]@{
            Name   = $_.BaseName
            Length = Get-ChildItem -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue -Attributes !o | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue | Select-Object -Property Sum -ExpandProperty Sum
        }
    }
    $Largest = $ProfileSizes | Sort-Object -Property Length -Descending | Select-Object -First 1

    $Size = $ProfileSizes | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue | Select-Object -Property Sum -ExpandProperty Sum

    $FormattedSize = Format-FileSize -Length $Size

    $AllProfiles = $ProfileSizes | Sort-Object -Property Length -Descending | ForEach-Object {
        $FormattedSizeUser = Format-FileSize -Length $_.Length
        "$($_.Name) $($FormattedSizeUser)"
    }

    Write-Host ('Total Size: ' + ("{0:N1}" -f ($Size / 1GB)))
    if ($customFieldGB) { Ninja-Property-Set -Name $CustomFieldGB -Value ("{0:N1}" -f ($Size / 1GB)) }

    Write-Host "All Profiles - $FormattedSize, $($AllProfiles -join ', ')"
    if ($customFieldDetail) { Ninja-Property-Set -Name $CustomFieldDetail -Value "All Profiles - $FormattedSize, $($AllProfiles -join ', ')" }

    if ($Max -and $Max -gt 0) {
        if ($Largest.Length -gt $Max * 1GB) {
            Write-Host "Found profile over the max size of $Max GB."
            Write-Host "$($Largest.Name) profile is $($Largest.Length / 1GB) GB"
            exit 1
        }
    }
    exit 0
}
end {
    
}
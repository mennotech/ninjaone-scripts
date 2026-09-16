# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Sleep
# ==============================================================================
#
# Description:
#   Used to delay automations in a queue.
#
# Metadata:
#   - NinjaOne Script ID: 100
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2025-06-06
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-06-06 17:56:15
#   - Active: True
# Script Variables (NinjaOne):
#   - seconds (INTEGER, Required): Seconds the script should sleep.
#     Default: 300
#
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
#Requires -Version 5.1

<#
.SYNOPSIS
    Simple sleep function
.DESCRIPTION
    Waits for the number of seconds then exits
.EXAMPLE
     -Seconds 60
#>

[CmdletBinding()]
param (
    [Parameter()]
    [Alias("S", "Sec")]
    [Int]$Seconds = 60
)

begin {
    if ($env:Seconds -and $env:Seconds -notlike "null") { $Seconds = $env:Seconds }
}
process {
    Write-Host "[info] $(Get-Date) - Sleeping for $Seconds seconds..."
    Start-Sleep -Seconds $Seconds
    Write-Host "[info] $(Get-Date) - Done sleeping."
    exit 0
}
end {
}

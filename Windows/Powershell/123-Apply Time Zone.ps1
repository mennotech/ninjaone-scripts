# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Apply Time Zone
# ==============================================================================
#
# Description:
#   Configures a specified time zone to the system
#
# Metadata:
#   - NinjaOne Script ID: 123
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Admin
#   - Created On: 2026-10-23
#   - Last Updated By: Roland Admin
#   - Last Updated: 2026-10-23 14:43:43
#   - Active: True
# Script Variables (NinjaOne):
#   - timeZone (TEXT, Optional): The windows timezone to set on the system
#     Default: Manitoba Standard Time
#
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
#Requires -Version 5.1
<#
.SYNOPSIS
    Applies an installed Windows time zone and reports it to NinjaOne.
.DESCRIPTION
    Checks that the requested Windows time zone ID is installed, applies it if
    necessary, and verifies the resulting ID. Does not install Windows updates
    or substitute a different zone when the requested ID is unavailable.

    At completion, writes the actual current time zone ID to the scriptResult
    device custom field, including after an application failure when readable.
    Any validation, application, verification, or reporting failure exits with 1.
.PARAMETER timeZone
    Windows time zone ID. Defaults to Manitoba Standard Time. The NinjaOne
    script variable timeZone overrides this parameter when set and not "null".
.OUTPUTS
    Informational messages and the actual time zone ID in scriptResult.
.NOTES
    Run as Local System or an administrator on Windows with PowerShell 5.1+.
    The scriptResult device text field must allow Automations write access.
    Ninja-Property-Set must be available, including when testing locally.

    Version History:
    1.0.0 - 2026-10-23 - Validate, apply, verify, and report the Windows time zone.
.LINK
    https://github.com/mennotech/ninjaone-scripts
.LICENSE
    MIT License. See LICENSE in the repository root.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$timeZone = "Manitoba Standard Time"
)

function Test-IsElevated {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

$ExitCode = 0

try {
    if ($env:timeZone -and $env:timeZone -notlike "null") {
        $timeZone = $env:timeZone
    }

    if ([string]::IsNullOrWhiteSpace($timeZone)) {
        throw "The timeZone value must be a Windows time zone ID."
    }
    $timeZone = $timeZone.Trim()

    if (-not (Test-IsElevated)) {
        throw "This script requires administrative privileges. Run as Local System or an administrator."
    }

    # Check reporting availability before making a system change.
    if (-not (Get-Command -Name "Ninja-Property-Set" -ErrorAction SilentlyContinue)) {
        throw "Ninja-Property-Set is unavailable. Run through NinjaOne with scriptResult configured for Automations write access."
    }

    $RequestedZone = Get-TimeZone -ListAvailable -ErrorAction Stop |
        Where-Object { $_.Id -eq $timeZone } |
        Select-Object -First 1

    if ($null -eq $RequestedZone) {
        throw "Time zone '$timeZone' is not installed on this PC. Install applicable Windows time zone updates and rerun. No replacement time zone was applied."
    }

    $CurrentZone = Get-TimeZone -ErrorAction Stop
    if ($CurrentZone.Id -ne $RequestedZone.Id) {
        Write-Host "Changing time zone from '$($CurrentZone.Id)' to '$($RequestedZone.Id)'."
        Set-TimeZone -Id $RequestedZone.Id -ErrorAction Stop
    }
    else {
        Write-Host "Time zone is already '$($RequestedZone.Id)'. No change needed."
    }

    $CurrentZone = Get-TimeZone -ErrorAction Stop
    if ($CurrentZone.Id -ne $RequestedZone.Id) {
        throw "Time zone verification failed. Expected '$($RequestedZone.Id)', but found '$($CurrentZone.Id)'."
    }

    Write-Host "Verified time zone: '$($CurrentZone.Id)'."
}
catch {
    $ExitCode = 1
    Write-Error "Could not apply time zone '$timeZone': $($_.Exception.Message)" -ErrorAction Continue
}
finally {
    try {
        $ActualZone = Get-TimeZone -ErrorAction Stop
        Ninja-Property-Set -Name "scriptResult" -Value $ActualZone.Id -ErrorAction Stop
        Write-Host "Updated scriptResult to '$($ActualZone.Id)'."
    }
    catch {
        $ExitCode = 1
        Write-Error "Could not report the current time zone to scriptResult: $($_.Exception.Message)" -ErrorAction Continue
    }
}

exit $ExitCode

# ==============================================================================
# Script Name: Enable Wireguard for Non-Admins
# ==============================================================================
#
# Description:
#   Give local users access to launch and run Wireguard. Note this grants all local users access to make system wide network changes.
#
# Metadata:
#   - NinjaOne Script ID: 120
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2026-07-31
#   - Last Updated By: Roland Penner
#   - Last Updated: 2026-07-31 18:25:59
#   - Active: True
#
# Script Variables (NinjaOne):
#   - wireguarduser (TEXT, Optional): The user to be given access to run WireGuard (domain\user)
#
# ==============================================================================
# NinjaOne Script Variable:
# WireGuardUser
# Example: CONTOSO\jdoe

$WireGuardUser = $env:WireGuardUser

if ([string]::IsNullOrWhiteSpace($WireGuardUser)) {
    Write-Output "ERROR: WireGuardUser parameter was not supplied."
    exit 1
}

# Enable WireGuard LimitedOperatorUI
$wgKey = "HKLM:\SOFTWARE\WireGuard"

if (-not (Test-Path $wgKey)) {
    New-Item -Path $wgKey -Force | Out-Null
}

New-ItemProperty -Path $wgKey `
    -Name "LimitedOperatorUI" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

Write-Output "WireGuard LimitedOperatorUI enabled."

$GroupName = "Network Configuration Operators"

try {
    $members = Get-LocalGroupMember -Group $GroupName -ErrorAction Stop

    $existing = $members | Where-Object {
        $_.Name -ieq $WireGuardUser
    }

    if ($existing) {
        Write-Output "'$WireGuardUser' is already a member of '$GroupName'."
        exit 0
    }

    Add-LocalGroupMember `
        -Group $GroupName `
        -Member $WireGuardUser `
        -ErrorAction Stop

    $verify = Get-LocalGroupMember -Group $GroupName |
        Where-Object { $_.Name -ieq $WireGuardUser }

    if ($verify) {
        Write-Output "SUCCESS: Added '$WireGuardUser' to '$GroupName'."
        exit 0
    }
    else {
        Write-Output "ERROR: Verification failed."
        exit 1
    }
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
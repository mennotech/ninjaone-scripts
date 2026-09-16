# ==============================================================================
# Script Name: Store Bitlocker Recovery Key to NinjaOne
# ==============================================================================
#
# Description:
#   No description provided
#
# Metadata:
#   - NinjaOne Script ID: 121
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2026-08-07
#   - Last Updated By: Roland Admin
#   - Last Updated: 2026-08-07 16:44:12
#   - Active: True
## ==============================================================================
#Requires -Version 5.1
<#
.SYNOPSIS
    Collects local BitLocker recovery keys and writes them to NinjaOne custom fields.

.DESCRIPTION
    Designed for NinjaOne automation running as Local System or local administrator.

    Updates two NinjaOne custom fields:

        bitlockerKeys
            Secure field.
            Contains ONLY the full BitLocker recovery passwords as a comma-separated list.
            Example:
                123456-123456-123456-123456-123456-123456-123456-123456,654321-654321-654321-654321-654321-654321-654321-654321

        bitlockerKeyIds
            Multiline text field.
            Contains device identity, BitLocker Key Protector IDs, and redacted recovery keys.
            Does NOT contain full recovery passwords.

    The script does NOT print full recovery passwords to NinjaOne script output.

.NOTES
    NinjaOne custom field names must be the internal field names, not labels.

    Required NinjaOne custom fields:
        bitlockerKeys    - secure field
        bitlockerKeyIds  - multiline text field

    Recommended permissions:
        Automations: Read/Write
        Technicians: restrict bitlockerKeys tightly
        API: restrict bitlockerKeys tightly
#>

$ErrorActionPreference = "Stop"

# =========================
# Configuration
# =========================

$BitLockerKeysFieldName   = "bitlockerKeys"
$BitLockerKeyIdsFieldName = "bitlockerKeyIds"

# Keep this false. The secure field receives full keys, but script output should not.
$LogFullKeysToOutput = $false

# If true, the script exits with failure if no usable RecoveryPassword protectors are found.
# Usually leave false so Ninja fields still get diagnostic details.
$FailIfNoRecoveryPasswords = $false

# If true, duplicate recovery passwords are removed before writing bitlockerKeys.
$DeduplicateRecoveryPasswords = $true

# =========================
# Helper Functions
# =========================

function Get-SafeValue {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [string]$Fallback = "Unknown"
    )

    if ($null -eq $Value) {
        return $Fallback
    }

    $StringValue = [string]$Value

    if ([string]::IsNullOrWhiteSpace($StringValue)) {
        return $Fallback
    }

    return $StringValue.Trim()
}

function Test-CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $Command = Get-Command -Name $CommandName -ErrorAction SilentlyContinue
    return ($null -ne $Command)
}

function Set-NinjaCustomField {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$FieldValue
    )

    # Preferred NinjaOne PowerShell helper.
    if (Test-CommandExists -CommandName "Ninja-Property-Set") {
        Ninja-Property-Set $FieldName $FieldValue
        return
    }


    throw "Could not find Ninja-Property-Set or ninjarmm-cli.exe. Cannot update NinjaOne custom field '$FieldName'."
}

function Get-DeviceIdentity {
    $Identity = [ordered]@{}

    $Identity.ComputerName = Get-SafeValue -Value $env:COMPUTERNAME

    try {
        $Bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $Identity.SerialNumber = Get-SafeValue -Value $Bios.SerialNumber
    }
    catch {
        $Identity.SerialNumber = "Unknown"
    }

    try {
        $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $Identity.Manufacturer = Get-SafeValue -Value $ComputerSystem.Manufacturer
        $Identity.Model        = Get-SafeValue -Value $ComputerSystem.Model
        $Identity.Domain       = Get-SafeValue -Value $ComputerSystem.Domain
        $Identity.UserName     = Get-SafeValue -Value $ComputerSystem.UserName -Fallback "No interactive user"
    }
    catch {
        $Identity.Manufacturer = "Unknown"
        $Identity.Model        = "Unknown"
        $Identity.Domain       = "Unknown"
        $Identity.UserName     = "Unknown"
    }

    try {
        $CsProduct = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop
        $Identity.DeviceUuid = Get-SafeValue -Value $CsProduct.UUID
    }
    catch {
        $Identity.DeviceUuid = "Unknown"
    }

    return $Identity
}

function Protect-RecoveryPasswordForDisplay {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$RecoveryPassword
    )

    if ([string]::IsNullOrWhiteSpace($RecoveryPassword)) {
        return "Not available"
    }

    $Parts = $RecoveryPassword -split "-"

    if ($Parts.Count -eq 8) {
        return "$($Parts[0])-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-$($Parts[7])"
    }

    # Fallback protection for unexpected formats.
    if ($RecoveryPassword.Length -gt 12) {
        return "$($RecoveryPassword.Substring(0, 6))...[REDACTED]...$($RecoveryPassword.Substring($RecoveryPassword.Length - 6))"
    }

    return "[REDACTED]"
}

function Get-BitLockerRecoveryInfo {
    if (-not (Test-CommandExists -CommandName "Get-BitLockerVolume")) {
        try {
            Import-Module BitLocker -ErrorAction Stop
        }
        catch {
            throw "Get-BitLockerVolume is not available and the BitLocker module could not be imported. $($_.Exception.Message)"
        }
    }

    $Results = New-Object System.Collections.Generic.List[object]
    $Volumes = @(Get-BitLockerVolume -ErrorAction Stop)

    foreach ($Volume in $Volumes) {
        $MountPoint           = Get-SafeValue -Value $Volume.MountPoint -Fallback "Unknown"
        $VolumeType           = Get-SafeValue -Value $Volume.VolumeType -Fallback "Unknown"
        $ProtectionStatus     = Get-SafeValue -Value $Volume.ProtectionStatus -Fallback "Unknown"
        $LockStatus           = Get-SafeValue -Value $Volume.LockStatus -Fallback "Unknown"
        $EncryptionPercentage = Get-SafeValue -Value $Volume.EncryptionPercentage -Fallback "Unknown"
        $EncryptionMethod     = Get-SafeValue -Value $Volume.EncryptionMethod -Fallback "Unknown"

        $RecoveryProtectors = @(
            $Volume.KeyProtector |
                Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
        )

        if ($RecoveryProtectors.Count -eq 0) {
            $Results.Add([pscustomobject]@{
                MountPoint           = $MountPoint
                VolumeType           = $VolumeType
                ProtectionStatus     = $ProtectionStatus
                LockStatus           = $LockStatus
                EncryptionPercentage = $EncryptionPercentage
                EncryptionMethod     = $EncryptionMethod
                KeyProtectorId       = "None"
                RecoveryPassword     = ""
                RedactedKey          = "Not available"
                HasRecoveryPassword  = $false
                StatusMessage        = "No RecoveryPassword protector found"
            })

            continue
        }

        foreach ($Protector in $RecoveryProtectors) {
            $KeyProtectorId   = Get-SafeValue -Value $Protector.KeyProtectorId -Fallback "Unknown"
            $RecoveryPassword = Get-SafeValue -Value $Protector.RecoveryPassword -Fallback ""
            $HasRecoveryPassword = -not [string]::IsNullOrWhiteSpace($RecoveryPassword)
            $RedactedKey = Protect-RecoveryPasswordForDisplay -RecoveryPassword $RecoveryPassword

            $Results.Add([pscustomobject]@{
                MountPoint           = $MountPoint
                VolumeType           = $VolumeType
                ProtectionStatus     = $ProtectionStatus
                LockStatus           = $LockStatus
                EncryptionPercentage = $EncryptionPercentage
                EncryptionMethod     = $EncryptionMethod
                KeyProtectorId       = $KeyProtectorId
                RecoveryPassword     = $RecoveryPassword
                RedactedKey          = $RedactedKey
                HasRecoveryPassword  = $HasRecoveryPassword
                StatusMessage        = if ($HasRecoveryPassword) { "RecoveryPassword found" } else { "RecoveryPassword not accessible" }
            })
        }
    }

    return $Results
}

function Format-BitLockerKeysSecureFieldValue {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$RecoveryInfo,

        [Parameter(Mandatory = $true)]
        [bool]$Deduplicate
    )

    $Keys = @(
        $RecoveryInfo |
            Where-Object { $_.HasRecoveryPassword -eq $true -and -not [string]::IsNullOrWhiteSpace($_.RecoveryPassword) } |
            ForEach-Object { $_.RecoveryPassword.Trim() }
    )

    if ($Deduplicate) {
        $Keys = @($Keys | Select-Object -Unique)
    }

    return ($Keys -join ",")
}

function Format-BitLockerKeyIdsFieldValue {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$DeviceIdentity,

        [Parameter(Mandatory = $true)]
        [object[]]$RecoveryInfo
    )

    $Lines = New-Object System.Collections.Generic.List[string]


    if (-not $RecoveryInfo -or $RecoveryInfo.Count -eq 0) {
        $Lines.Add("No BitLocker volumes or recovery key IDs found.")
        return ($Lines -join "`r`n")
    }


    foreach ($Item in $RecoveryInfo) {
        $Lines.Add($Item.KeyProtectorId)
    }

    $Lines.Add("")
    $Lines.Add("==========================")
    $Lines.Add("Last Updated        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    $Lines.Add("Computer Name       : $($DeviceIdentity.ComputerName)")
    $Lines.Add("Serial Number       : $($DeviceIdentity.SerialNumber)")
    $Lines.Add("Manufacturer        : $($DeviceIdentity.Manufacturer)")
    $Lines.Add("Model               : $($DeviceIdentity.Model)")
    $Lines.Add("Device UUID         : $($DeviceIdentity.DeviceUuid)")
    $Lines.Add("Domain              : $($DeviceIdentity.Domain)")
    $Lines.Add("Logged On User      : $($DeviceIdentity.UserName)")
    $Lines.Add("")


    $Index = 1

    foreach ($Item in $RecoveryInfo) {
        $Lines.Add("Entry $Index")
        $Lines.Add("-------")
        $Lines.Add("Volume              : $($Item.MountPoint)")
        $Lines.Add("Volume Type         : $($Item.VolumeType)")
        $Lines.Add("Protection Status   : $($Item.ProtectionStatus)")
        $Lines.Add("Lock Status         : $($Item.LockStatus)")
        $Lines.Add("Encryption Percent  : $($Item.EncryptionPercentage)")
        $Lines.Add("Encryption Method   : $($Item.EncryptionMethod)")
        $Lines.Add("Key Protector ID    : $($Item.KeyProtectorId)")
        $Lines.Add("Recovery Key        : $($Item.RedactedKey)")
        $Lines.Add("Key Available       : $($Item.HasRecoveryPassword)")
        $Lines.Add("Status              : $($Item.StatusMessage)")
        $Lines.Add("")
        $Index++
    }

    return ($Lines -join "`r`n")
}

function Format-SafeOutputValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return ($Value -replace '\b\d{6}(?:-\d{6}){7}\b', '[REDACTED-BITLOCKER-RECOVERY-PASSWORD]')
}

# =========================
# Main
# =========================

try {
    Write-Host "Starting BitLocker recovery field update."

    $DeviceIdentity = Get-DeviceIdentity

    Write-Host "Device identity:"
    Write-Host "  Computer Name : $($DeviceIdentity.ComputerName)"
    Write-Host "  Serial Number : $($DeviceIdentity.SerialNumber)"
    Write-Host "  Manufacturer  : $($DeviceIdentity.Manufacturer)"
    Write-Host "  Model         : $($DeviceIdentity.Model)"
    Write-Host "  Device UUID   : $($DeviceIdentity.DeviceUuid)"
    Write-Host ""

    $RecoveryInfo = @(Get-BitLockerRecoveryInfo)

    $RecoveryPasswordCount = @(
        $RecoveryInfo |
            Where-Object { $_.HasRecoveryPassword -eq $true }
    ).Count

    $KeyProtectorIdCount = @(
        $RecoveryInfo |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.KeyProtectorId) -and
                $_.KeyProtectorId -ne "None"
            }
    ).Count

    Write-Host "BitLocker recovery password count : $RecoveryPasswordCount"
    Write-Host "BitLocker key protector ID count  : $KeyProtectorIdCount"
    Write-Host ""

    $BitLockerKeysValue = Format-BitLockerKeysSecureFieldValue `
        -RecoveryInfo $RecoveryInfo `
        -Deduplicate $DeduplicateRecoveryPasswords

    $BitLockerKeyIdsValue = Format-BitLockerKeyIdsFieldValue `
        -DeviceIdentity $DeviceIdentity `
        -RecoveryInfo $RecoveryInfo

    Write-Host "Updating NinjaOne secure custom field '$BitLockerKeysFieldName' with comma-separated recovery keys..."
    Set-NinjaCustomField -FieldName $BitLockerKeysFieldName -FieldValue $BitLockerKeysValue
    Write-Host "Successfully updated '$BitLockerKeysFieldName'."

    Write-Host "Updating NinjaOne multiline custom field '$BitLockerKeyIdsFieldName' with key IDs and redacted keys..."
    Set-NinjaCustomField -FieldName $BitLockerKeyIdsFieldName -FieldValue $BitLockerKeyIdsValue
    Write-Host "Successfully updated '$BitLockerKeyIdsFieldName'."

    Write-Host ""
    Write-Host "Safe output summary:"
    Write-Host "===================="
    Write-Host (Format-SafeOutputValue -Value $BitLockerKeyIdsValue)

    if ($LogFullKeysToOutput) {
        Write-Host ""
        Write-Host "WARNING: LogFullKeysToOutput is enabled. Full keys would normally appear here, but output is still redacted by safety design."
        Write-Host (Format-SafeOutputValue -Value $BitLockerKeysValue)
    }
    else {
        Write-Host ""
        Write-Host "Full recovery passwords were written only to the NinjaOne secure field '$BitLockerKeysFieldName'."
        Write-Host "Full recovery passwords were intentionally not printed to script output."
    }

    if ($FailIfNoRecoveryPasswords -and $RecoveryPasswordCount -eq 0) {
        throw "No BitLocker RecoveryPassword protectors were found. Custom fields were updated with diagnostic information."
    }

    Write-Host ""
    Write-Host "Completed successfully."
    exit 0
}
catch {
    Write-Error "Failed to update NinjaOne BitLocker custom fields. $($_.Exception.Message)"
    exit 1
}

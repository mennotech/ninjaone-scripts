# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Disable MOW File Zone Information
# ==============================================================================
#
# Description:
#   Disabled the Mark of Web or SaveZoneInformation configuration in windows through a registry entry
#
# Metadata:
#   - NinjaOne Script ID: 118
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2026-05-15
#   - Last Updated By: Roland Penner
#   - Last Updated: 2026-05-15 18:29:32
#   - Active: True
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments"

# Ensure the key exists
If (!(Test-Path $path)) {
    New-Item -Path $path -Force | Out-Null
}

# Set the value
New-ItemProperty -Path $path -Name "SaveZoneInformation" -Value 1 -PropertyType DWord -Force
# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Reset Outlook Plugins Folders and Configs
# ==============================================================================
#
# Description:
#   No description provided
#
# Metadata:
#   - NinjaOne Script ID: 119
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2026-05-20
#   - Last Updated By: Roland Penner
#   - Last Updated: 2026-05-20 15:37:53
#   - Active: True
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
# Close Outlook if running
Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | ForEach-Object {
    $_.CloseMainWindow() | Out-Null
    Write-Output "Closing Outlook..."
    Start-Sleep -Seconds 5
    if (!$_.HasExited) {
        Stop-Process -Id $_.Id -Force
    }
}

# Path to Wef folder
$wefPath = "$($env:LOCALAPPDATA)\Microsoft\Office\16.0\Wef"

# Delete Wef folder and contents
if (Test-Path $wefPath) {
    Write-Output "Removing $wefPath"
    Remove-Item -Path $wefPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "Wef folder cleanup complete."
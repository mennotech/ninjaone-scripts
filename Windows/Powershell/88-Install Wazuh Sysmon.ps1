# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Install Wazuh Sysmon
# ==============================================================================
#
# Description:
#   No description provided
#
# Metadata:
#   - NinjaOne Script ID: 88
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2025-04-28
#   - Last Updated By: Roland Admin
#   - Last Updated: 2026-02-21 03:25:36
#   - Active: True
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
if (Test-Path "C:\ProgramData\Wazuh-Sysmon") {
  Write-Host "Already installed, cancelling."
} else {
  C:
  CD \ProgramData
  MD Wazuh-Sysmon
  CD Wazuh-Sysmon
  Invoke-WebRequest -Uri https://download.sysinternals.com/files/Sysmon.zip -OutFile Sysmon.zip
  Expand-Archive -Path Sysmon.zip -DestinationPath .
  Invoke-WebRequest -Uri https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml -OutFile sysmonconfig.xml
  .\sysmon -accepteula -i sysmonconfig.xml
  .\sysmon -c
}

# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Upgrade Duo Windows Login
# ==============================================================================
#
# Description:
#   No description provided
#
# Metadata:
#   - NinjaOne Script ID: 106
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64
#   - Created By: Roland Penner
#   - Created On: 2025-07-17
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-07-17 21:26:59
#   - Active: True
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
<#
.SYNOPSIS
This script downloads the latest Duo Windows Logon installer, extracts it, and installs it silently.

.PARAMETER 
None

#>
function Main {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "Downloading Zip file"
    Curl https://dl.duosecurity.com/DuoWinLogon_MSIs_Policies_and_Documentation-latest.zip -o "C:\duo-win-login-latest.zip"

    if (Test-Path "C:\duo-win-login-latest.zip") {
        Write-Host "Expanding Archive"
        Expand-Archive "C:\duo-win-login-latest.zip" -DestinationPath C:\duo-win-login-latest -Force
    } else {
        Write-Host "Download failed"
        Remove-TemporaryFiles
        exit 1
    }

    if (Test-Path "C:\duo-win-login-latest\DuoWindowsLogon64.msi") {
        Write-Host "Running Installer"
        Start-Process -FilePath "msiexec.exe" -ArgumentList "-qn /i C:\duo-win-login-latest\DuoWindowsLogon64.msi" -Wait -NoNewWindow
    } else {
        Write-Host "Installer not found."
        Remove-TemporaryFiles
        Exit 2
    }

    Write-Host "Installation complete. Cleaning up temporary files."
    Remove-TemporaryFiles
}

function Remove-TemporaryFiles {
    if (Test-Path "C:\duo-win-login-latest\") {
        Write-Host "Cleaning up zip folder"
        Remove-Item -Recurse -Force "C:\duo-win-login-latest\"
    }
    if (Test-Path "C:\duo-win-login-latest.zip") {
        Write-Host "Removing zip file"
        Remove-Item -Force "C:\duo-win-login-latest.zip"
    }
}

Main

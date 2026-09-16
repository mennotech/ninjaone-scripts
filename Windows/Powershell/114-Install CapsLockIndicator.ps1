# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Install CapsLockIndicator
# ==============================================================================
#
# Description:
#   Installs and registers CapsLockIndicator from github.
#
# Metadata:
#   - NinjaOne Script ID: 114
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64
#   - Created By: Roland Penner
#   - Created On: 2025-12-22
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-12-22 17:09:23
#   - Active: True
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy or update CapsLockIndicator from GitHub for all users
.DESCRIPTION
    Downloads latest CapsLockIndicator, installs to Program Files, registers for all users startup, and applies custom configuration
#>

# Configuration
$installPath = "$($env:ProgramData)\CapsLockIndicator"
$gitHubRepo = "jonaskohl/CapsLockIndicator"
$exeName = "CapsLockIndicator.exe"
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$registryName = "CapsLockIndicator"

# Get latest release info from GitHub API
try {
    $apiUrl = "https://api.github.com/repos/$gitHubRepo/releases/latest"
    $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
    $latestVersion = $release.tag_name
    $downloadUrl = ($release.assets | Where-Object { $_.name -like "*.exe" }).browser_download_url
    
    if (-not $downloadUrl) {
        Write-Error "Failed to find executable asset in latest release"
        exit 1
    }
    
    Write-Output "Latest version available: $latestVersion"
} catch {
    Write-Error "Failed to fetch latest release info: $_"
    exit 1
}

# Check current installation
$currentVersion = $null
$needsInstall = $true
$exePath = Join-Path $installPath $exeName

if (Test-Path $exePath) {
    try {
        $versionInfo = (Get-Item $exePath).VersionInfo
        $currentVersion = $versionInfo.FileVersion
        Write-Output "Current version installed: $currentVersion"
        
        # Compare versions (simple string comparison)
        if ($currentVersion -eq $latestVersion.TrimStart('v')) {
            Write-Output "Already running latest version"
            $needsInstall = $false
        } else {
            Write-Output "Update available: $currentVersion -> $latestVersion"
        }
    } catch {
        Write-Warning "Could not determine current version: $_"
    }
}

# Download and install if needed
if ($needsInstall) {
    Write-Output "Installing CapsLockIndicator $latestVersion..."
    
    # Create install directory
    try {
        if (-not (Test-Path $installPath)) {
            New-Item -ItemType Directory -Path $installPath -Force | Out-Null
        }
    } catch {
        Write-Error "Failed to create installation directory: $_"
        exit 1
    }
    
    # Download latest executable
    $tempFile = Join-Path $env:TEMP "CapsLockIndicator_temp.exe"
    try {
        Write-Output "Downloading from: $downloadUrl"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile -UseBasicParsing
    } catch {
        Write-Error "Failed to download CapsLockIndicator: $_"
        exit 1
    }
    
    # Stop existing process if running
    Get-Process | Where-Object { $_.Path -eq $exePath } | Stop-Process -Force -ErrorAction SilentlyContinue
    
    # Copy to install location
    try {
        Copy-Item -Path $tempFile -Destination $exePath -Force
        Remove-Item $tempFile -Force
        Write-Output "Installed to: $exePath"
    } catch {
        Write-Error "Failed to copy executable to installation directory: $_"
        exit 1
    }
}


# Set folder permissions for Users group to have write access
try {
    # Get Users group using SID (works across all language versions of Windows)
    $usersSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")
    $usersGroup = $usersSID.Translate([System.Security.Principal.NTAccount])
    
    # Get current ACL
    $acl = Get-Acl -Path $installPath
    
    # Create new access rule: Users group with Modify rights (includes Write)
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $usersGroup,
        "Modify",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    
    # Add the rule and apply
    $acl.SetAccessRule($accessRule)
    Set-Acl -Path $installPath -AclObject $acl
    
    Write-Output "Granted write permissions to Users group on: $installPath"
} catch {
    Write-Error "Failed to set folder permissions: $_"
    exit 1
}


# Configure startup for all users
try {
    $registryValue = "`"$exePath`""
    Set-ItemProperty -Path $registryPath -Name $registryName -Value $registryValue -Type String -Force
    Write-Output "Registered for all users startup"
} catch {
    Write-Error "Failed to update registry for startup: $_"
    exit 1
}

# Download and save configuration from NinjaOne custom field
try {
    $configContent = Ninja-Property-Get capsLockIndicatorConfiguration
    
    if ($configContent) {
        # Normalize line endings to Windows format (CRLF)
        $configContent = $configContent -replace "`r`n", "`n"
        $configPath = Join-Path $installPath "usercfg"
        $configContent -split "`n" | Set-Content -Path $configPath -Encoding UTF8
        Write-Output "Configuration saved to: $configPath"
    } else {
        Write-Output "No configuration found in custom field 'capsLockIndicatorConfiguration'"
    }
} catch {
    Write-Error "Failed to write configuration file: $_"
    exit 1
}

Write-Output "CapsLockIndicator deployment completed successfully"
exit 0

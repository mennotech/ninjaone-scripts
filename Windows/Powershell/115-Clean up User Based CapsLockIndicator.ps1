# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Clean up User Based CapsLockIndicator
# ==============================================================================
#
# Description:
#   Searches and removes CapsLockIndicator folders and registry keys.
#
# Metadata:
#   - NinjaOne Script ID: 115
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2025-12-22
#   - Last Updated By: Roland Admin
#   - Last Updated: 2026-02-21 03:12:30
#   - Active: True
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
#Requires -Version 5.1
<#
.SYNOPSIS
    Remove per-user CapsLockIndicator installations from all user profiles
.DESCRIPTION
    Cleans up CapsLockIndicator folders and registry entries from individual user profiles
#>

$cleanupCount = 0
$appFolderName = "CapsLockIndicator"
$registryValueName = "CapsLock Indicator"
$processName = "CLI"

Write-Output "Starting CapsLockIndicator per-user cleanup..."

# Get all user profiles (excluding system accounts)
try {
    $userProfiles = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }
    
    Write-Output "Found $($userProfiles.Count) user profile(s) to check"
} catch {
    Write-Error "Failed to enumerate user profiles: $_"
    exit 1
}

foreach ($profile in $userProfiles) {
    $username = $profile.Name
    $appPath = Join-Path $profile.FullName "AppData\Roaming\$appFolderName"
    $foundInstallation = $false
    
    Write-Output "`nChecking profile: $username"
    
    # Check and remove application folder
    if (Test-Path $appPath) {
        $foundInstallation = $true
        Write-Output "  Found installation at: $appPath"
        
        try {
            # Stop any running CapsLockIndicator processes for this user
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue | 
                Where-Object { $_.Path -like "$appPath\*" }
            
            if ($processes) {
                Write-Output "  Stopping $($processes.Count) running process(es)..."
                $processes | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
            }
            
            # Remove the folder
            Remove-Item -Path $appPath -Recurse -Force -ErrorAction Stop
            Write-Output "  Removed folder: $appPath"
        } catch {
            Write-Error "Failed to remove folder for user '$username': $_"
        }
    }
    
    # Handle registry cleanup
    try {
        # Try to get user SID from profile path
        $profileItem = Get-Item $profile.FullName -ErrorAction SilentlyContinue
        $userSID = $null
        
        # Method 1: Get SID from local user account
        try {
            $localUser = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
            if ($localUser) {
                $userSID = $localUser.SID.Value
            }
        } catch {
            # Get-LocalUser may not be available or user may be domain account
        }
        
        # Method 2: Get SID from registry ProfileList
        if (-not $userSID) {
            $profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
            $profiles = Get-ChildItem $profileListPath -ErrorAction SilentlyContinue
            foreach ($p in $profiles) {
                $profilePath = (Get-ItemProperty $p.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
                if ($profilePath -eq $profile.FullName) {
                    $userSID = $p.PSChildName
                    break
                }
            }
        }
        
        if ($userSID) {
            # Check if user hive is already loaded
            $registryPath = "Registry::HKEY_USERS\$userSID\Software\Microsoft\Windows\CurrentVersion\Run"
            $hiveLoaded = Test-Path "Registry::HKEY_USERS\$userSID"
            $tempHiveLoaded = $false
            
            # If not loaded, try to load the user's registry hive
            if (-not $hiveLoaded) {
                $ntUserDatPath = Join-Path $profile.FullName "NTUSER.DAT"
                if (Test-Path $ntUserDatPath) {
                    try {
                        $tempHiveName = "TempHive_$userSID"
                        & reg load "HKU\$tempHiveName" $ntUserDatPath 2>&1 | Out-Null
                        $registryPath = "Registry::HKEY_USERS\$tempHiveName\Software\Microsoft\Windows\CurrentVersion\Run"
                        $tempHiveLoaded = $true
                        Write-Output "  Loaded registry hive for: $username"
                    } catch {
                        Write-Warning "  Could not load registry hive for user '$username': $_"
                    }
                }
            }
            
            # Remove registry entry if it exists
            if (Test-Path $registryPath) {
                try {
                    $runKey = Get-ItemProperty -Path $registryPath -Name $registryValueName -ErrorAction SilentlyContinue
                    if ($runKey) {
                        Remove-ItemProperty -Path $registryPath -Name $registryValueName -Force -ErrorAction Stop
                        Write-Output "  Removed registry entry for: $username"
                        $foundInstallation = $true
                    }
                } catch {
                    Write-Error "Failed to remove registry entry for user '$username': $_"
                }
            }
            
            # Unload temporary hive if we loaded it
            if ($tempHiveLoaded) {
                try {
                    [gc]::Collect()
                    Start-Sleep -Milliseconds 500
                    & reg unload "HKU\TempHive_$userSID" 2>&1 | Out-Null
                    Write-Output "  Unloaded registry hive for: $username"
                } catch {
                    Write-Warning "  Could not unload registry hive for user '$username': $_"
                }
            }
        } else {
            Write-Warning "  Could not determine SID for user: $username"
        }
    } catch {
        Write-Error "Failed to process registry for user '$username': $_"
    }
    
    if ($foundInstallation) {
        $cleanupCount++
        Write-Output "  Cleanup completed for: $username"
    } else {
        Write-Output "  No per-user installation found for: $username"
    }
}

Write-Output "`n========================================="
Write-Output "Cleanup Summary:"
Write-Output "  Processed: $($userProfiles.Count) user profile(s)"
Write-Output "  Cleaned: $cleanupCount installation(s)"
Write-Output "========================================="

exit 0

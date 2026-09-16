# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Upgrade Notepad++ to v8.9.1
# ==============================================================================
#
# Description:
#   No description provided
#
# Metadata:
#   - NinjaOne Script ID: 117
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2026-02-03
#   - Last Updated By: Roland Penner
#   - Last Updated: 2026-02-03 20:23:18
#   - Active: True
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
# Requires: PowerShell 5+
# Purpose : Uninstall existing Notepad++ and install v8.9.1 (x64) silently
# Exit codes:
#   0  = Success
#   10 = Uninstall failed
#   20 = Download failed
#   30 = Install failed

# Region: Setup
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$InstallerUrl = 'https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.9.1/npp.8.9.1.Installer.x64.exe'
$TempDir      = Join-Path $env:TEMP "NPP_Deploy"
$Installer    = Join-Path $TempDir "npp.8.9.1.Installer.x64.exe"
$LogDir       = Join-Path $env:ProgramData "NinjaOne\Logs"
$LogFile      = Join-Path $LogDir "NotepadPP_Deploy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Ensure directories exist
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

# Simple logging helper
function Write-Log {
    param([string]$Message)
    $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line  = "[$stamp] $Message"
    $line | Tee-Object -FilePath $LogFile -Append
}

Write-Log "=== Notepad++ Deployment started ==="

# Region: Helper to get existing Notepad++ uninstaller(s)
function Get-NppUninstallEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $entries = foreach ($p in $paths) {
        try {
            Get-ItemProperty -Path $p -ErrorAction Stop | Where-Object {
                $_.DisplayName -match '^Notepad(\+\+|plusplus)'
            }
        } catch { }
    }
    return $entries
}

# Region: Try to gracefully close Notepad++ if running
function Stop-NppIfRunning {
    try {
        $procs = Get-Process -Name 'notepad++' -ErrorAction SilentlyContinue
        if ($procs) {
            Write-Log "Notepad++ process detected, attempting to stop."
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    } catch {
        Write-Log "Warning: Failed to stop Notepad++ process. $_"
    }
}

# Region: Uninstall
function Uninstall-NotepadPP {
    $entries = Get-NppUninstallEntries
    if (-not $entries) {
        Write-Log "No existing Notepad++ installation found."
        return $true
    }

    Stop-NppIfRunning

    $allOk = $true

    foreach ($e in $entries) {
        $displayName   = $e.DisplayName
        $uninstallStr  = $e.UninstallString
        Write-Log "Found installed: $displayName"
        if (-not $uninstallStr) {
            Write-Log "No UninstallString found for $displayName; skipping."
            continue
        }

        try {
            # Normalize command for silent uninstall
            if ($uninstallStr -match 'msiexec\.exe') {
                # Extract product code if present; otherwise pass through
                # Ensure silent switches
                $cmd = $uninstallStr
                if ($cmd -notmatch '/x' -and $cmd -notmatch '/X') {
                    # If DisplayName matched but no /x, try to infer ProductCode
                    if ($e.PSChildName -match '^\{.*\}$') {
                        $cmd = "msiexec.exe /x $($e.PSChildName) /qn /norestart"
                    } else {
                        # Best-effort: replace /I with /x if present
                        $cmd = $cmd -replace '/i', '/x'
                        if ($cmd -notmatch '/x') { $cmd += ' /x' }
                        if ($cmd -notmatch '/qn') { $cmd += ' /qn' }
                        if ($cmd -notmatch '/norestart') { $cmd += ' /norestart' }
                    }
                } else {
                    if ($cmd -notmatch '/qn') { $cmd += ' /qn' }
                    if ($cmd -notmatch '/norestart') { $cmd += ' /norestart' }
                }
                Write-Log "Uninstall (MSI): $cmd"
                $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $cmd" -Wait -PassThru -WindowStyle Hidden
                if ($p.ExitCode -ne 0) {
                    Write-Log "MSI uninstall exit code: $($p.ExitCode)"
                    $allOk = $false
                }
            } else {
                # EXE uninstaller, e.g. "C:\Program Files\Notepad++\uninstall.exe"
                # Ensure silent switch /S (Notepad++/NSIS)
                $exe, $args = $null, $null

                # Some uninstall strings include quotes and args; parse naively
                if ($uninstallStr.StartsWith('"')) {
                    $exe = $uninstallStr.Split('"')[1]
                    $args = $uninstallStr.Substring($uninstallStr.IndexOf('"',1)+1).Trim()
                } else {
                    $parts = $uninstallStr.Split(' ',2)
                    $exe   = $parts[0]
                    $args  = if ($parts.Count -gt 1) { $parts[1] } else { '' }
                }

                if ([string]::IsNullOrWhiteSpace($args)) { $args = '/S' }
                elseif ($args -notmatch '(^| )/S( |$)') { $args += ' /S' }

                Write-Log "Uninstall (EXE): `"$exe`" $args"
                $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
                if ($p.ExitCode -ne 0) {
                    Write-Log "EXE uninstall exit code: $($p.ExitCode)"
                    $allOk = $false
                }
            }
        } catch {
            Write-Log "Error uninstalling $displayName : $_"
            $allOk = $false
        }
    }

    # Optional: verify removal
    $post = Get-NppUninstallEntries
    if ($post) {
        Write-Log "Notepad++ still detected after uninstall attempt."
        $allOk = $false
    } else {
        Write-Log "Notepad++ successfully uninstalled (or not present)."
    }

    return $allOk
}

# Region: Download installer
function Download-Installer {
    try {
        Write-Log "Downloading installer from $InstallerUrl to $Installer"
        # Use BITS if available for resilience; fallback to Invoke-WebRequest
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            Start-BitsTransfer -Source $InstallerUrl -Destination $Installer -ErrorAction Stop
        } else {
            Invoke-WebRequest -Uri $InstallerUrl -OutFile $Installer -UseBasicParsing -ErrorAction Stop
        }
        if (-not (Test-Path $Installer)) {
            throw "Download completed but file not found at $Installer"
        }
        # Quick size sanity check
        $size = (Get-Item $Installer).Length
        if ($size -lt 1024kb) {
            throw "Downloaded file size too small ($size bytes) - possible network/content issue."
        }
        Write-Log "Download OK. Size: $([math]::Round($size/1MB,2)) MB"
        return $true
    } catch {
        Write-Log "Download failed: $_"
        return $false
    }
}

# Region: Install
function Install-NotepadPP {
    try {
        if (-not (Test-Path $Installer)) {
            Write-Log "Installer not found at $Installer"
            return $false
        }

        # Silent switches for Notepad++ NSIS installer
        $args = '/S'  # Silent install

        Write-Log "Installing Notepad++ v8.9.1: `"$Installer`" $args"
        $p = Start-Process -FilePath $Installer -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
        if ($p.ExitCode -ne 0) {
            Write-Log "Installer exit code: $($p.ExitCode)"
            return $false
        }

        # Basic post-install verification
        $exePaths = @(
            "$env:ProgramFiles\Notepad++\notepad++.exe",
            "$env:ProgramFiles(x86)\Notepad++\notepad++.exe"
        )
        $installed = $exePaths | Where-Object { Test-Path $_ }
        if ($installed) {
            Write-Log "Install verification OK. Path(s): $($installed -join ', ')"
            return $true
        } else {
            Write-Log "Install verification failed: notepad++.exe not found."
            return $false
        }
    } catch {
        Write-Log "Install failed: $_"
        return $false
    }
}

# ===================== MAIN =====================
$uninstalled = Uninstall-NotepadPP
if (-not $uninstalled) {
    Write-Log "Uninstall phase reported failure."
    Write-Log "=== Notepad++ Deployment finished with errors (uninstall) ==="
    Exit 10
}

$downloaded = Download-Installer
if (-not $downloaded) {
    Write-Log "=== Notepad++ Deployment finished with errors (download) ==="
    Exit 20
}

$installed = Install-NotepadPP
if (-not $installed) {
    Write-Log "=== Notepad++ Deployment finished with errors (install) ==="
    Exit 30
}

Write-Log "=== Notepad++ Deployment completed successfully ==="

# Cleanup (optional)
try {
    Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
} catch { }

Exit 0

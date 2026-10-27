# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Install Windows Updates
# ==============================================================================
#
# Description:
#   This script scans for available Windows Updates and then installs non optional updates.
#
# Metadata:
#   - NinjaOne Script ID: 125
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64
#   - Created By: Roland Penner
#   - Created On: 2026-10-27
#   - Last Updated By: Roland Penner
#   - Last Updated: 2026-10-27 14:14:14
#   - Active: True
#
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
#Requires -Version 5.1
<#
.SYNOPSIS
    Scans for and installs pending non-optional Windows Updates using the
    built-in Windows Update Agent, then reports the updates applied.
.DESCRIPTION
    Intended for devices whose Windows Updates are managed outside NinjaOne
    (Windows Update, WSUS, or Windows Update for Business). Uses the native
    Windows Update Agent COM API with the device's default update service, so
    the existing Windows Update/WSUS configuration is respected.

    Only updates that are not installed, not hidden, and not optional
    (BrowseOnly) are installed. Optional updates such as preview cumulative
    updates and optional drivers are skipped. Updates that may prompt for user
    input are skipped because they cannot complete unattended.

    The script never reboots the device. If a reboot is required, it is
    reported so a NinjaOne native reboot can be scheduled.
.OUTPUTS
    Console output listing each update found, downloaded, and installed, with
    a final summary of applied and failed updates and the reboot status.
    Exit code 0 when all updates installed (or none were needed), 1 on any
    failure.
.NOTES
    Run as Local System or an administrator on Windows with PowerShell 5.1+.
    The Windows Update service (wuauserv) must not be disabled.
    Large updates can take a long time; set an adequate NinjaOne timeout.

    Version History:
    1.0.0 - 2026-10-27 - Scan, download, and install non-optional Windows Updates and report results.
.LINK
    https://github.com/mennotech/ninjaone-scripts
.LICENSE
    MIT License. See LICENSE in the repository root.
#>

[CmdletBinding()]
param()

begin {
    function Test-IsElevated {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Get-UpdateKB {
        param($Update)
        $kbList = @($Update.KBArticleIDs | ForEach-Object { "KB$($_)" })
        if ($kbList.Count -gt 0) { return ($kbList -join ", ") }
        return "N/A"
    }

    function Get-ResultCodeText {
        param([int]$Code)
        switch ($Code) {
            0 { "Not Started" }
            1 { "In Progress" }
            2 { "Succeeded" }
            3 { "Succeeded With Errors" }
            4 { "Failed" }
            5 { "Aborted" }
            default { "Unknown ($($Code))" }
        }
    }

    function Format-HResult {
        param([int]$HResult)
        return ("0x{0:X8}" -f $HResult)
    }

    $ExitCode = 0
    $Results = New-Object System.Collections.Generic.List[object]
    $RebootRequired = $false

    if (-not (Test-IsElevated)) {
        Write-Error "This script requires administrative privileges. Run as Local System or an administrator."
        exit 1
    }

    $WUService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    if ($null -eq $WUService) {
        Write-Error "The Windows Update service (wuauserv) was not found on this device."
        exit 1
    }
    if ($WUService.StartType -eq "Disabled") {
        Write-Error "The Windows Update service (wuauserv) is disabled. Updates are managed outside NinjaOne, so this script will not change the service configuration."
        exit 1
    }
}

process {
    try {
        $Session = New-Object -ComObject "Microsoft.Update.Session" -ErrorAction Stop
        $Session.ClientApplicationID = "NinjaOne - Install Windows Updates"

        $SystemInfo = New-Object -ComObject "Microsoft.Update.SystemInfo" -ErrorAction SilentlyContinue
        if ($SystemInfo -and $SystemInfo.RebootRequired) {
            Write-Warning "A reboot is already pending from a previous update. Some updates may not install until the device restarts."
        }

        # BrowseOnly=0 excludes updates Windows Update presents as optional.
        $Criteria = "IsInstalled=0 and IsHidden=0 and BrowseOnly=0"
        $Searcher = $Session.CreateUpdateSearcher()
        Write-Host "Checking for updates using the device's configured update service..."
        $SearchResult = $Searcher.Search($Criteria)

        if ($SearchResult.ResultCode -ne 2) {
            Write-Warning "Update search completed with result: $(Get-ResultCodeText -Code $SearchResult.ResultCode)"
        }

        if ($SearchResult.Updates.Count -eq 0) {
            Write-Host "No pending non-optional updates found. The device is up to date."
            return
        }

        Write-Host "Found $($SearchResult.Updates.Count) pending update(s):"
        $ToDownload = New-Object -ComObject "Microsoft.Update.UpdateColl"
        foreach ($Update in $SearchResult.Updates) {
            $kb = Get-UpdateKB -Update $Update
            if ($Update.InstallationBehavior.CanRequestUserInput) {
                Write-Host "  - [Skipped: requires user input] $($kb) - $($Update.Title)"
                $Results.Add([PSCustomObject]@{ KB = $kb; Title = $Update.Title; Result = "Skipped (requires user input)" })
                continue
            }
            if (-not $Update.EulaAccepted) {
                $Update.AcceptEula()
            }
            Write-Host "  - $($kb) - $($Update.Title)"
            [void]$ToDownload.Add($Update)
        }

        if ($ToDownload.Count -eq 0) {
            Write-Host "No updates can be installed unattended."
            return
        }

        Write-Host "Downloading $($ToDownload.Count) update(s)..."
        $Downloader = $Session.CreateUpdateDownloader()
        $Downloader.Updates = $ToDownload
        $DownloadResult = $Downloader.Download()

        $ToInstall = New-Object -ComObject "Microsoft.Update.UpdateColl"
        for ($i = 0; $i -lt $ToDownload.Count; $i++) {
            $Update = $ToDownload.Item($i)
            if ($Update.IsDownloaded) {
                [void]$ToInstall.Add($Update)
            }
            else {
                $UpdateResult = $DownloadResult.GetUpdateResult($i)
                $Reason = "Download $(Get-ResultCodeText -Code $UpdateResult.ResultCode) ($(Format-HResult -HResult $UpdateResult.HResult))"
                Write-Warning "Download failed: $(Get-UpdateKB -Update $Update) - $($Update.Title) - $($Reason)"
                $Results.Add([PSCustomObject]@{ KB = (Get-UpdateKB -Update $Update); Title = $Update.Title; Result = $Reason })
                $ExitCode = 1
            }
        }

        if ($ToInstall.Count -eq 0) {
            Write-Error "None of the updates could be downloaded." -ErrorAction Continue
            $ExitCode = 1
            return
        }

        Write-Host "Installing $($ToInstall.Count) update(s)..."
        $Installer = $Session.CreateUpdateInstaller()
        if ($Installer.IsBusy) {
            throw "Another Windows Update installation is already in progress. Try again later."
        }
        $Installer.Updates = $ToInstall
        $Installer.AllowSourcePrompts = $false
        $Installer.ForceQuiet = $true
        $InstallResult = $Installer.Install()
        $RebootRequired = [bool]$InstallResult.RebootRequired

        for ($i = 0; $i -lt $ToInstall.Count; $i++) {
            $Update = $ToInstall.Item($i)
            $UpdateResult = $InstallResult.GetUpdateResult($i)
            $ResultText = Get-ResultCodeText -Code $UpdateResult.ResultCode
            if ($UpdateResult.ResultCode -notin 2, 3) {
                $ResultText = "$($ResultText) ($(Format-HResult -HResult $UpdateResult.HResult))"
                $ExitCode = 1
            }
            $Results.Add([PSCustomObject]@{ KB = (Get-UpdateKB -Update $Update); Title = $Update.Title; Result = $ResultText })
        }
    }
    catch {
        $ExitCode = 1
        $HResultText = if ($_.Exception.HResult) { " ($(Format-HResult -HResult $_.Exception.HResult))" } else { "" }
        Write-Error "Windows Update failed: $($_.Exception.Message)$($HResultText)" -ErrorAction Continue
    }
}

end {
    if ($Results.Count -gt 0) {
        $Applied = @($Results | Where-Object { $_.Result -like "Succeeded*" })
        $NotApplied = @($Results | Where-Object { $_.Result -notlike "Succeeded*" })

        Write-Host ""
        Write-Host "===== Updates Applied ($($Applied.Count)) ====="
        if ($Applied.Count -gt 0) {
            $Applied | ForEach-Object { Write-Host "  [$($_.Result)] $($_.KB) - $($_.Title)" }
        }
        else {
            Write-Host "  None"
        }

        if ($NotApplied.Count -gt 0) {
            Write-Host ""
            Write-Host "===== Updates Not Applied ($($NotApplied.Count)) ====="
            $NotApplied | ForEach-Object { Write-Host "  [$($_.Result)] $($_.KB) - $($_.Title)" }
        }

        Write-Host ""
        if ($RebootRequired) {
            Write-Host "A reboot is required to complete installation. Schedule a reboot using NinjaOne's native reboot action."
        }
        else {
            Write-Host "No reboot required."
        }
    }

    exit $ExitCode
}

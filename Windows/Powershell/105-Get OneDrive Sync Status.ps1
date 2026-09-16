# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Get OneDrive Sync Status
# ==============================================================================
#
# Description:
#   This script checks the OneDrive sync status for all users on the machine using the ODSyncUtil PowerShell module.
#
# Metadata:
#   - NinjaOne Script ID: 105
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64
#   - Created By: Roland Penner
#   - Created On: 2025-06-24
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-06-27 20:31:43
#   - Active: True
# Script Variables (NinjaOne):
#   - rmmonedrivestatefield (TEXT, Optional): The Number field to populate with the value of the maximum state found
#     Default: OneDriveState
#   - rmmonedrivedetailsfield (TEXT, Optional): The String field to populate with the OneDrive status details
#     Default: OneDriveDetails
#   - updatescheduledtask (TEXT, Optional): Set this value to "true" if you want to update the action for the task if it is found.
#     Default: false
#
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
<#
.SYNOPSIS
    Retrieves the OneDrive sync status for all users currently running OneDrive on the local machine and optionally updates a specified RMM field with the results.

.DESCRIPTION
    This script downloads the ODSyncUtil.exe library from github. It then creates a scheduled task to run as the logged in user.
    The scheduled task writes the current OneDrive Sync status to the user's %APPDATA%\ODSyncStatus.json file.
    The script checks all user folder paths for the ODSyncStatus.json file and then updates any RMM fields as specified.

.PARAMETER
    -RMMOneDriveStateField: Specifies the RMM field to populate with the Maximum State Value found
    -RMMOneDriveDetailsField: Specifies the RMM field to populate with the details of OneDrive sync status
    -UpdateScheduledTask: Specifies whether to update the scheduled task with the new action. Default is "false".
   
.OUTPUTS
    Outputs a the status of the script, if any OneDrive status is above 0 then it will also print out the Sync Details

.NOTES
    2025-06-24: Initial version of the script.
    
.LINK
    https://github.com/mennotech/rmm-scripts/blob/main/powershell/Get-OneDrive-Sync-Status.ps1

.LICENSE
    This script is released under the MIT License.
#>
[CmdletBinding()]
param (
    [Parameter()]
    [String]$RMMOneDriveStateField = "",
    [Parameter()]
    [String]$RMMOneDriveDetailsField = "",
    [Parameter()]
    [String]$UpdateScheduledTask = "false"
)

begin {

$TaskCommand = '"C:\Program Files\ODSyncUtil\run-hidden64.exe"'
$TaskArguments = '"C:\Program Files\ODSyncUtil\ODSyncUtil.exe" -s "%APPDATA%\ODSyncStatus.json"'

$TaskXML  = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>Mennotech</Author>
    <Description>Checks the status of OneDrive Sync and writes it to a file in the user's AppData folder</Description>
    <URI>\QueryOneDriveStatus</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Repetition>
        <Interval>PT60M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <ExecutionTimeLimit>PT1M</ExecutionTimeLimit>
      <Enabled>true</Enabled>
      <Delay>PT15M</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-545</GroupId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$TaskCommand</Command>
      <Arguments>$TaskArguments</Arguments>
    </Exec>
  </Actions>
</Task>
"@


    # Test if the script is running with elevated privileges
    function Test-IsElevated { 
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    if (-not (Test-IsElevated)) {
        Write-Error "This script requires administrative privileges. Please run it as an administrator."
        exit 1
    }

    # If script form variables are used replace the command line parameters.
    if ($env:RMMOneDriveStateField -and $env:RMMOneDriveStateField -notlike "null") { $RMMOneDriveStateField = $env:RMMOneDriveStateField }
    if ($env:RMMOneDriveDetailsField -and $env:RMMOneDriveDetailsField -notlike "null") { $RMMOneDriveDetailsField = $env:RMMOneDriveDetailsField }
    if ($env:UpdateScheduledTask -and $env:UpdateScheduledTask -eq "true") { $UpdateScheduledTask = $true } 

    # Make sure the ODSyncUtil module is installed
    if (-not (Test-Path -Path "$env:PROGRAMFILES\ODSyncUtil\ODSyncUtil.exe")) {
        Write-Host "ODSyncUtil module is not installed. Installing..."
        # Github release URL for ODSyncUtil
        $moduleUrl = "https://github.com/rodneyviana/ODSyncUtil/releases/download/1.0.6.5000/ODSyncUtil-64-bit.zip"
        $modulePath = "$env:TEMP\ODSyncUtil-64-bit.zip"
        Invoke-WebRequest -Uri $moduleUrl -OutFile $modulePath
        Expand-Archive -Path $modulePath -DestinationPath "$env:PROGRAMFILES\ODSyncUtil" -Force
        Remove-Item -Path $modulePath -Force
        
        if (-not (Test-Path -Path "$env:PROGRAMFILES\ODSyncUtil\ODSyncUtil.exe")) {
            Write-Error "Failed to install ODSyncUtil module. Please check the installation path."
            exit 1
        } else {
            Write-Host "ODSyncUtil module downloaded and extracted successfully."
        }                
    }


    # Make sure the run-hidden64.exe module is installed
    if (-not (Test-Path -Path "$env:PROGRAMFILES\ODSyncUtil\run-hidden64.exe")) {
        Write-Host "run-hidden64.exe module is not installed. Installing..."
        # Github release URL for run-hidden64.exe
        # Note: This is a different module than ODSyncUtil, it is used to run the ODSyncUtil.exe in the background
        $moduleUrl = "https://github.com/stax76/run-hidden/releases/download/v1.4/run-hidden64.exe"
        $modulePath = "$env:PROGRAMFILES\ODSyncUtil\run-hidden64.exe"
        Invoke-WebRequest -Uri $moduleUrl -OutFile $modulePath
        
        if (-not (Test-Path -Path "$env:PROGRAMFILES\ODSyncUtil\run-hidden64.exe")) {
            Write-Error "Failed to install run-hidden64 module. Please check the installation path."
            exit 1
        } else {
            Write-Host "run-hidden64 module downloaded and extracted successfully."
        }                
    }

}
process {
    $StatusDetails = ""
    $StateCodes = @()

    # Check if the Scheduled Task for ODSyncUtil is present
    $taskName = "QueryOneDriveStatus"
    $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $taskExists) {
        Write-Host "Scheduled Task '$taskName' not found. Creating a new task..."
        try {
            $task = Register-ScheduledTask -TaskName $taskName -XML $TaskXML -Force -ErrorAction Stop
            Start-Sleep -Seconds 2            
            $task | Start-ScheduledTask
            Start-Sleep -Seconds 2
        } catch {
            Write-Error "Failed to create Scheduled Task '$taskName'. Error: $_"
            return
        }
        $StatusDetail += "Scheduled Task '$taskName' created successfully."
    } else {
        $lastRunTime = ($taskExists | Get-ScheduledTaskInfo).LastRunTime
        $StatusDetails += "Scheduled Task '$taskName' already exists. Last run: $lastRunTime"
        
        if ($UpdateScheduledTask -eq "true") {
            try {
                #Updating Scheduled task
                Write-Host "Updating scheduled task with new Action"
                $NewAction = New-ScheduledTaskAction -Execute $TaskCommand -Argument $TaskArguments
                $null = Set-ScheduledTask -TaskName $taskName -Action $NewAction
            } catch {
                Write-Error "Failed to update Scheduled Task '$taskName'. Error: $_"            
            }          
        }    
    }


    # Get a list of user profiles on the machine using WMI
    $UserProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object {
        $_.Special -eq $false -and
        $_.LocalPath -notlike "C:\Users\Default*" -and
        $_.LocalPath -notlike "C:\Users\Public*" -and
        $_.LocalPath -notlike "C:\Users\Default User*"
    }

    if (-not $UserProfiles) {
        return
    }

    
    foreach ($UserProfile in $UserProfiles) {
        $FilePath = "$($UserProfile.LocalPath)\AppData\Roaming\ODSyncStatus.json"
        if (-not (Test-Path -Path $FilePath)) {
            continue
        } else {
            $LastUpdated = (Get-Item -Path $FilePath).LastWriteTime
            $StatusDetails += "`nLast updated: $LastUpdated - $FilePath"
                        
            $ODSyncStatus = Get-Content -Path $FilePath | ConvertFrom-Json
            $StateCodes += ($ODSyncStatus | Where-Object { $_.FolderPath -ne "" }).CurrentState            
            $StatusDetails += ($ODSyncStatus | Where-Object { $_.FolderPath -ne "" } | Format-List UserName, CurrentState, CurrentStateString, ServiceName, Label, FolderPath, QuotaLabel | Out-String)            
        }
    }

    $MaxStateCode =  ( $StateCodes | Sort-Object -Descending)[0]
    
    
    Write-Host "Max StateCode: $MaxStateCode"
    Write-Host $StatusDetails
    

    # Update the RMM fields with the sync status
    if ($RMMOneDriveStateField -and $RMMOneDriveStateField -notlike "null") {
        Write-Host "Updating RMM field '$RMMOneDriveStateField' with OneDrive sync status..."
        try {
            Ninja-Property-Set -Name $RMMOneDriveStateField -Value $MaxStateCode
            Write-Host "RMM field '$RMMOneDriveStateField' updated successfully."
        } catch {
            Write-Error "Failed to update RMM field '$RMMOneDriveStateField'. Error: $_"
        }                        
    }

    if ($RMMOneDriveDetailsField -and $RMMOneDriveDetailsField -notlike "null") {
        Write-Host "Updating RMM field '$RMMOneDriveDetailsField' with OneDrive sync details..."
        try {            
            Ninja-Property-Set -Name $RMMOneDriveDetailsField -Value $StatusDetails
            Write-Host "RMM field '$RMMOneDriveDetailsField' updated successfully."
        } catch {
            Write-Error "Failed to update RMM field '$RMMOneDriveDetailsField'. Error: $_"
        }
    }

    
}

end {

}
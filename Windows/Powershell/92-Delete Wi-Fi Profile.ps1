# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Delete Wi-Fi Profile
# ==============================================================================
#
# Description:
#   Runs netsh delete command for specified Wi-Fi SSID
#
# Metadata:
#   - NinjaOne Script ID: 92
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2025-05-30
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-06-18 22:37:11
#   - Active: True
# Script Variables (NinjaOne):
#   - ssid (TEXT, Required): The SSID that you wish to delete
#
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
#Requires -Version 5.1

<#
.SYNOPSIS
    This script deletes a specified Wi-Fi profile from the system.
.DESCRIPTION
    This script deletes a specified Wi-Fi profile from the system using the netsh command.
    It checks for existing Wi-Fi profiles, deletes the specified profile if it exists, and handles errors appropriately.
    The script can be run with the following parameters:
        -SSID: Specifies the Wi-Fi SSID/name to delete.
        -AuthType: Specifies the authentication type (WPA2 or WPA3).
        -PreSharedKeyCustomField: Specifies the name of a secure custom field that contains the preshared key.
        -Overwrite: If the profile already exists, overwrite it.
    
.EXAMPLE
    -SSID "cookiemonster" -PreSharedKeyCustomField "WifiPass"

    Retrieving preshared key from secure custom field 'WifiPassword'.
    Successfully retrieved preshared key.
    Creating XML for Wi-Fi profile 'cookiemonster'.
    Saving XML to C:\Windows\Temp\wi-fi.251d970a-299d-48a2-a256-341542983464.xml
    Importing Wi-Fi profile 'cookiemonster' from XML.
    ExitCode: 0
    Profile 'cookiemonster' is added on interface Wi-Fi.
    Removing xml.

.PARAMETER
    -SSID "ReplaceMeWithYourWi-FiName"
        Specify the Wi-Fi SSID/name.
    -AuthType "WPA3SAE"
        Select either WPA2 authentication or WPA3..
    -PreSharedKeyCustomField "ReplaceMeWithASecureCustomField"
        Specify the name of a secure custom field that contains the preshared key.
    -Overwrite
        If the profile already exists overwrite it.

.NOTES
    2025-06-18 Initial Release

.LICENSE
    This script is released under the MIT License.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [String]$SSID
)

begin {
    # If script form variables are used replace the command line parameters.
    if ($env:ssid -and $env:ssid -notlike "null") { $SSID = $env:ssid }

    # If no Wi-Fi interfaces exist or the wireless service is not running, display an error message indicating that they are required.
    try {
        $WifiAdapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.PhysicalMediaType -match '802\.11' }
        if (!$WifiAdapters) {
            Write-Host -Object "[Error] No Wi-Fi network interfaces exist on the system."
            exit 1
        }

        $WlanService = Get-Service -Name 'wlansvc' -ErrorAction Stop | Where-Object { $_.Status -eq 'Running' }
        if (!$WlanService) {
            Write-Host -Object "[Error] The service 'wlansvc' is not running. The service 'wlansvc' is required to add the Wi-Fi network."
            exit 1
        }
    }
    catch {
        Write-Host -Object "[Error] Unable to verify if a Wi-Fi network interface exists and that the 'wlansvc' service is running."
        Write-Host -Object "[Error] $($_.Exception.Message)"
        exit 1
    }

    # If $SSID is provided, trim any leading or trailing whitespace from the SSID
    if ($SSID) {
        $SSID = $SSID.Trim()
    }

    # If $SSID is not provided or is empty after trimming, display an error message indicating the SSID is required
    if (!$SSID) {
        Write-Host -Object "[Error] The Wi-Fi SSID/name is required to add Wi-Fi profile to the device."
        exit 1
    }

    # Measure the length of the SSID and store it in $SSIDCharcterLength
    $SSIDCharacterLength = $SSID | Measure-Object -Character | Select-Object -ExpandProperty Characters
    # If the SSID length is greater than 32 characters, display an error message indicating the SSID length constraint
    if ($SSIDCharacterLength -gt 32) {
        Write-Host -Object "[Error] The SSID '$SSID' is greater than 32 characters. SSIDs must be less than or equal to 32 characters."
        exit 1
    }


    function Get-NinjaProperty {
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
            [String]$Name,
            [Parameter()]
            [String]$Type,
            [Parameter()]
            [String]$DocumentName
        )
        
        # Initialize a hashtable for documentation parameters
        $DocumentationParams = @{}
        if ($DocumentName) { $DocumentationParams["DocumentName"] = $DocumentName }
        
        # Define types that need options
        $NeedsOptions = "DropDown", "MultiSelect"
        
        if ($DocumentName) {
            # Check for invalid type 'Secure'
            if ($Type -Like "Secure") { throw [System.ArgumentOutOfRangeException]::New("$Type is an invalid type! Please check here for valid types. https://ninjarmm.zendesk.com/hc/en-us/articles/16973443979789-Command-Line-Interface-CLI-Supported-Fields-and-Functionality") }
        
            # Retrieve the property value from Ninja Document
            Write-Host "Retrieving value from Ninja Document..."
            $NinjaPropertyValue = Ninja-Property-Docs-Get -AttributeName $Name @DocumentationParams 2>&1
        
            # Retrieve property options if needed
            if ($NeedsOptions -contains $Type) {
                $NinjaPropertyOptions = Ninja-Property-Docs-Options -AttributeName $Name @DocumentationParams 2>&1
            }
        }
        else {
            # Retrieve the property value directly
            $NinjaPropertyValue = Ninja-Property-Get -Name $Name 2>&1
        
            # Retrieve property options if needed
            if ($NeedsOptions -contains $Type) {
                $NinjaPropertyOptions = Ninja-Property-Options -Name $Name 2>&1
            }
        }
        
        # Throw exceptions if errors occur during retrieval
        if ($NinjaPropertyValue.Exception) { throw $NinjaPropertyValue }
        if ($NinjaPropertyOptions.Exception) { throw $NinjaPropertyOptions }
        
        # Throw an exception if the property value is empty
        if (-not $NinjaPropertyValue) {
            throw [System.NullReferenceException]::New("The Custom Field '$Name' is empty!")
        }
        
        # Process the property value based on its type
        switch ($Type) {
            "Attachment" {
                $NinjaPropertyValue | ConvertFrom-Json
            }
            "Checkbox" {
                [System.Convert]::ToBoolean([int]$NinjaPropertyValue)
            }
            "Date or Date Time" {
                $UnixTimeStamp = $NinjaPropertyValue
                $UTC = (Get-Date "1970-01-01 00:00:00").AddSeconds($UnixTimeStamp)
                $TimeZone = [TimeZoneInfo]::Local
                [TimeZoneInfo]::ConvertTimeFromUtc($UTC, $TimeZone)
            }
            "Decimal" {
                [double]$NinjaPropertyValue
            }
            "Device Dropdown" {
                $NinjaPropertyValue | ConvertFrom-Json
            }
            "Device MultiSelect" {
                $NinjaPropertyValue | ConvertFrom-Json
            }
            "Dropdown" {
                $Options = $NinjaPropertyOptions -replace '=', ',' | ConvertFrom-Csv -Header "GUID", "Name"
                $Options | Where-Object { $_.GUID -eq $NinjaPropertyValue } | Select-Object -ExpandProperty Name
            }
            "Integer" {
                [int]$NinjaPropertyValue
            }
            "MultiSelect" {
                $Options = $NinjaPropertyOptions -replace '=', ',' | ConvertFrom-Csv -Header "GUID", "Name"
                $Selection = ($NinjaPropertyValue -split ',').trim()
        
                foreach ($Item in $Selection) {
                    $Options | Where-Object { $_.GUID -eq $Item } | Select-Object -ExpandProperty Name
                }
            }
            "Organization Dropdown" {
                $NinjaPropertyValue | ConvertFrom-Json
            }
            "Organization Location Dropdown" {
                $NinjaPropertyValue | ConvertFrom-Json
            }
            "Organization Location MultiSelect" {
                $NinjaPropertyValue | ConvertFrom-Json
            }
            "Organization MultiSelect" {
                $NinjaPropertyValue | ConvertFrom-Json
            }
            "Time" {
                $Seconds = $NinjaPropertyValue
                $UTC = ([timespan]::fromseconds($Seconds)).ToString("hh\:mm\:ss")
                $TimeZone = [TimeZoneInfo]::Local
                $ConvertedTime = [TimeZoneInfo]::ConvertTimeFromUtc($UTC, $TimeZone)
        
                Get-Date $ConvertedTime -DisplayHint Time
            }
            default {
                $NinjaPropertyValue
            }
        }
    }

    function Test-IsElevated {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object System.Security.Principal.WindowsPrincipal($id)
        $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    if (!$ExitCode) {
        $ExitCode = 0
    }
}
process {
    # If the script is not running with elevated privileges, display an error and exit
    if (!(Test-IsElevated)) {
        Write-Host -Object "[Error] Access Denied. Please run with Administrator privileges."
        exit 1
    }


    # Define the paths for standard error and output logs
    $StandardErrorPath = "$env:TEMP\wi-fi.prof.$(New-Guid).err.log"
    $StandardOutputPath = "$env:TEMP\wi-fi.prof.$(New-Guid).out.log"

    # Define the arguments for the netsh command to show existing Wi-Fi profiles
    $ExistingProfilesArguments = @(
        "wlan"
        "show"
        "profiles"
    )
    
    # Define the arguments for starting the netsh process
    $ExistingProfilesProcessArguments = @{
        Wait                   = $True
        PassThru               = $True
        NoNewWindow            = $True
        ArgumentList           = $ExistingProfilesArguments
        RedirectStandardError  = $StandardErrorPath
        RedirectStandardOutput = $StandardOutputPath
        FilePath               = "$env:SystemRoot\System32\netsh.exe"
    }

    # Attempt to start the netsh process to show existing Wi-Fi profiles
    try {
        Write-Host -Object "Checking for existing Wi-Fi profiles"
        $ExistingProfilesProcess = Start-Process @ExistingProfilesProcessArguments -ErrorAction Stop
    }
    catch {
        # If an error occurs while starting netsh, display an error message and exit
        Write-Host -Object "[Error] Unable to check for existing Wi-Fi profiles."
        Write-Host -Object "[Error] $($_.Exception.Message)"
        exit 1
    }

    # Display the exit code of the netsh process
    Write-Host -Object "ExitCode: $($ExistingProfilesProcess.ExitCode)"

    # If the exit code indicates failure, display an error message
    if ($ExistingProfilesProcess.ExitCode -ne 0) {
        Write-Host -Object "[Error] Exit code does not indicate success. Failed to check for existing Wi-Fi profiles."
        $ExitCode = 1
    }

    # If the standard error log file exists, read its content
    if (Test-Path -Path $StandardErrorPath -ErrorAction SilentlyContinue) {
        $ExistingProfilesErrors = Get-Content -Path $StandardErrorPath -ErrorAction SilentlyContinue
        Remove-Item -Path $StandardErrorPath -Force -ErrorAction SilentlyContinue
    }

    # If there are any errors in the standard error log, display them
    if ($ExistingProfilesErrors) {
        Write-Host -Object "[Error] An error has occurred when executing netsh."

        $ExistingProfilesErrors | ForEach-Object {
            Write-Host -Object "[Error] $_"
        }

        $ExitCode = 1
    }

    # If the standard output log file exists, read and display its content
    if (Test-Path -Path $StandardOutputPath -ErrorAction SilentlyContinue) {
        $ExistingProfilesOutput = Get-Content -Path $StandardOutputPath -ErrorAction SilentlyContinue
        Remove-Item -Path $StandardOutputPath -Force -ErrorAction SilentlyContinue
    }

    if($ExistingProfilesOutput){
        # Prepare a CSV list to store the profile data
        $CSVData = New-Object System.Collections.Generic.List[string]
        $CSVData.Add("ProfileType,ProfileName")

        # Process the output to format it as CSV
        $ExistingProfilesOutput | Where-Object { $_ -match ':' -and $_ -notmatch 'Profiles on interface' } | ForEach-Object {
            $CSVData.Add(
                ($_ -replace "\s+:\s+",",").Trim()
            )
        }

        # Convert the CSV data to objects
        $ExistingProfiles = $CSVData | ConvertFrom-CSV

        # Check if the specified SSID is already present
        $ProfileToDelete = $ExistingProfiles | Where-Object { $_.ProfileName -like $SSID }

        # If the profile is found indicate that it will be delete
        if($ProfileToDelete){
            Write-Host -Object "Wi-Fi network profile '$SSID' was detected."
        }

        # If the profile is not found display an error and list existing profiles
        if(!$ProfileToDelete){
            $ExistingProfiles | Format-Table | Out-String | Write-Host
            Write-Host -Object "[Error] Wi-Fi network profile '$SSID' was not found."
            exit 1
        }
    }

    # Define the arguments for the netsh command
    $NetshArguments = @(
        "wlan"
        "delete"
        "profile"
        "name=`"$SSID`""
    )

    # Define the paths for standard error and output logs
    $StandardErrorPath = "$env:TEMP\wi-fi.$(New-Guid).err.log"
    $StandardOutputPath = "$env:TEMP\wi-fi.$(New-Guid).out.log"

    # Define the arguments for starting the netsh process
    $NetShProcessArguments = @{
        Wait                   = $True
        PassThru               = $True
        NoNewWindow            = $True
        ArgumentList           = $NetshArguments
        RedirectStandardError  = $StandardErrorPath
        RedirectStandardOutput = $StandardOutputPath
        FilePath               = "$env:SystemRoot\System32\netsh.exe"
    }

    # Attempt to start the netsh process to add the Wi-Fi profile
    try {
        Write-Host -Object "Deleting Wi-Fi profile '$SSID'."
        $NetshProcess = Start-Process @NetShProcessArguments -ErrorAction Stop
    }
    catch {
        # If an error occurs while starting netsh, display an error message and exit
        Write-Host -Object "[Error] Failed to start netsh."
        Write-Host -Object "[Error] $($_.Exception.Message)"
        exit 1
    }

    # Display the exit code of the netsh process
    Write-Host -Object "ExitCode: $($NetshProcess.ExitCode)"

    # If the exit code indicates failure, display an error message
    if ($NetshProcess.ExitCode -ne 0) {
        Write-Host -Object "[Error] Exit code does not indicate success. Failed to delete Wi-Fi profile."
        $ExitCode = 1
    }

    # If the standard error log file exists, read its content
    if (Test-Path -Path $StandardErrorPath -ErrorAction SilentlyContinue) {
        $NetshErrors = Get-Content -Path $StandardErrorPath -ErrorAction SilentlyContinue
        Remove-Item -Path $StandardErrorPath -Force -ErrorAction SilentlyContinue
    }

    # If there are any errors in the standard error log, display them
    if ($NetshErrors) {
        Write-Host -Object "[Error] An error has occurred when executing netsh."

        $NetshErrors | ForEach-Object {
            Write-Host -Object "[Error] $_"
        }

        $ExitCode = 1
    }

    # If the standard output log file exists, read and display its content
    if (Test-Path -Path $StandardOutputPath -ErrorAction SilentlyContinue) {
        $NetshOutput = Get-Content -Path $StandardOutputPath -ErrorAction SilentlyContinue
        Write-Host -Object $NetshOutput
        Remove-Item -Path $StandardOutputPath -Force -ErrorAction SilentlyContinue
    }

    exit $ExitCode
}
end {
    
    
    
}
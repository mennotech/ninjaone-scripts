# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Deploy Blackpoint SNAP Agent
# ==============================================================================
#
# Description:
#   No description provided
#
# Metadata:
#   - NinjaOne Script ID: 113
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64
#   - Created By: Roland Penner
#   - Created On: 2025-11-07
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-11-07 23:51:40
#   - Active: True
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
#.______    __          ___       ______  __  ___ .______     ______    __  .__   __. .___________.##  
#|   _  \  |  |        /   \     /      ||  |/  / |   _  \   /  __  \  |  | |  \ |  | |           |## 
#|  |_)  | |  |       /  ^  \   |  ,----'|  '  /  |  |_)  | |  |  |  | |  | |   \|  | `---|  |----`##  
#|   _  <  |  |      /  /_\  \  |  |     |    <   |   ___/  |  |  |  | |  | |  . `  |     |  |####### 
#|  |_)  | |  `----./  _____  \ |  `----.|  .  \  |  |      |  `--'  | |  | |  |\   |     |  |#######         
#|______/  |_______/__/     \__\ \______||__|\__\ | _|       \______/  |__| |__| \__|     |__|#######         
#####################################################################################################                                                                                                
####################################╔═╗╔╗╔╔═╗╔═╗///╔╦╗╔═╗╔═╗╔═╗╔╗╔╔═╗╔═╗#############################
####################################╚═╗║║║╠═╣╠═╝/// ║║║╣ ╠╣ ║╣ ║║║╚═╗║╣ ###### Ver 2.2 04/09/2021 ###
####################################╚═╝╝╚╝╩ ╩╩/////═╩╝╚═╝╚  ╚═╝╝╚╝╚═╝╚═╝#############################

###########
# EDIT ME
###########

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



#Customer UID found in URL From Blackpoint Portal
$blackpointInstallerUrl = Get-NinjaProperty -Name "blackpointInstallerUrl"

if ($blackpointInstallerUrl) {
  Write-Host "Blackpoint Installation started. URL: $blackpointInstallerUrl"
  
} else {
  Write-Host "No URL specified in field blackpointInstallerUrl"
  Exit 1
}

##############################
# DO NOT EDIT PAST THIS POINT
##############################

#Installer Name
$InstallerName = "snap_installer.exe"

#InstallsLocation
$InstallerPath =  Join-Path $env:TEMP $InstallerName

#Snap URL
$DownloadURL = $blackpointInstallerUrl

#Service Name
$SnapServiceName = "Snap"

#Enable Debug with 1
$DebugMode = 0 

#Failure message
$Failure = "Snap was not installed Successfully. Contact support@blackpointcyber.com if you need more help."

function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}


#Checking if the Service is Running
function Snap-Check($service)
{
    if (Get-Service $service -ErrorAction SilentlyContinue)
    {
        return $true
    }
    return $false
}

#Debug 
function Debug-Print ($message)
{
    if ($DebugMode -eq 1)
    {
        Write-Host "$(Get-TimeStamp) [DEBUG] $message"
    }
}

#Checking .NET Ver 4.6.1
function Net-Check {
    #Left in to help with troubleshooting
    #$cimreturn = (Get-CimInstance Win32_Operatingsystem | Select-Object -expand Caption -ErrorAction SilentlyContinue) 
    #$windowsfull =  $cimreturn
    #$WindowsSmall = $windowsfull.Split(" ")
    #[string]$WindowsSmall[0..($WindowsSmall.Count-2)]
    #If ($WindowsSmall -eq $Windows10) {  
    
    Debug-Print("Checking for .NET 4.6.1+...") 
    #Calls Net Ver 
        If (! (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release -gt 394254){
                   

        $NetError = "SNAP needs 4.6.1+ of .NET...EXITING" 
        Write-Host "$(Get-TimeStamp) $NetError"
        exit 0
        }
        
        {
        Debug-Print ("4.6.1+ Installed...")
        }
           
}

#Downloads file
function Download-Installer {
    Debug-Print("Downloading from provided $DownloadURL...")
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $Client = New-Object System.Net.Webclient
    try
    {
        $Client.DownloadFile($DownloadURL, $InstallerPath)
    }
    catch
    {
    $ErrorMsg = $_.Exception.Message
    Write-Host "$(Get-TimeStamp) $ErrorMsg"
    }
    If ( ! (Test-Path $InstallerPath) ) {
        $DownloadError = "Failed to download the SNAP Installation file from $DownloadURL"
        Write-Host "$(Get-TimeStamp) $DownloadError" 
        throw $Failure
    }
    Debug-Print ("Installer Downloaded to $InstallerPath...")

}

#Installation 
function Install-Snap {
    Debug-Print ("Verifying AV did not steal exe...")
    If (! (Test-Path $InstallerPath)) {
    {
        $AVError = "Something, or someone, deleted the file."
        Write-Host "$(Get-TimeStamp) $AVError"
        throw $Failure
    }
    }
    Debug-Print ("Unpacking and Installing agent...")
    Start-Process -NoNewWindow -FilePath $InstallerPath -ArgumentList "-y"    
}

function runMe {
    Debug-Print("Starting...")
    Debug-Print("Checking if SNAP is already installed...")
    If ( Snap-Check($SnapServiceName) )
    {
        $ServiceError = "SNAP is Already Installed...Bye." 
        Write-Host "$(Get-TimeStamp) $ServiceError"
        exit 0
    }
    Net-Check
    Download-Installer
    Install-Snap
  # Error-Test
    Write-Host "$(Get-TimeStamp) Snap Installed..."
}

try
{
    runMe
}
catch
{
    $ErrorMsg = $_.Exception.Message
    Write-Host "$(Get-TimeStamp) $ErrorMsg"
    exit 1
}
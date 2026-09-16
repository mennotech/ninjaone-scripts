# ==============================================================================
# Script Name: Collect Windows Diagnostics
# ==============================================================================
#
# Description:
#   Collects system, storage, networking, service, process, update, security, and Windows event log information. Time-based data defaults to the previous 24 hours. The output is written beneath C:\ProgramData by default.
#   NinjaRMM script form variables named LookbackHours, SamplingSeconds, OutputDirectory, and ExtensiveTest can override the matching command-line parameters.
#
# Metadata:
#   - NinjaOne Script ID: 122
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2026-08-25
#   - Last Updated By: Roland Admin
#   - Last Updated: 2026-09-16 03:42:20
#   - Active: True
# Script Variables (NinjaOne):
#   - lookbackhours (INTEGER, Optional): Number of hours of time-based diagnostic data to collect. Defaults to 24.
#   - outputdirectory (TEXT, Optional): Directory in which the diagnostic ZIP archive is created.
#   - samplingseconds (INTEGER, Optional): Number of seconds to sample performance counters. Defaults to 60 and may be set as high as 900 seconds (15 minutes).
#   - extensiveTest (CHECKBOX, Optional): Collect per-processor counters, a WPR CPU trace, and additional native event logs.
#     Default: false
#
# ==============================================================================
<#
.SYNOPSIS
    Collects Windows diagnostic information and saves it as a ZIP archive.

.DESCRIPTION
    Collects system, storage, networking, service, process, update, security,
    and Windows event log information. Time-based data defaults to the previous
    24 hours. The output is written beneath C:\ProgramData by default.

    NinjaRMM script form variables named LookbackHours, SamplingSeconds,
    OutputDirectory, and ExtensiveTest can override the matching command-line
    parameters.

.PARAMETER LookbackHours
    Number of hours of time-based diagnostic data to collect. Defaults to 24.

.PARAMETER SamplingSeconds
    Number of seconds to sample performance counters. Defaults to 60 and may be
    set as high as 900 seconds (15 minutes).

.PARAMETER OutputDirectory
    Directory in which the diagnostic ZIP archive is created.

.PARAMETER ExtensiveTest
    Collects per-logical-processor counters, a WPR CPU trace, and additional
    native event logs.

.EXAMPLE
    .\Collect-Windows-Diagnostics.ps1

.EXAMPLE
    .\Collect-Windows-Diagnostics.ps1 -LookbackHours 168 -SamplingSeconds 300

.EXAMPLE
    .\Collect-Windows-Diagnostics.ps1 -SamplingSeconds 300 -ExtensiveTest

.OUTPUTS
    Writes collection status and the final ZIP archive path to standard output.

.NOTES
    Run as an administrator for access to all diagnostic sources. A failure in
    one diagnostic source is recorded without stopping the remaining collection.
    2026-08-25: Initial version of the script.
    2026-08-25: Added sampled performance, findings, storage health, and power diagnostics.
    2026-09-15: Added extensive CPU tracing, WLAN reporting, and native event log exports.

.LINK
    https://github.com/mennotech/rmm-scripts/blob/main/powershell/Collect-Windows-Diagnostics.ps1

.LICENSE
    This script is released under the MIT License.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [ValidateRange(1, 8760)]
    [int]$LookbackHours = 24,

    [Parameter()]
    [ValidateRange(1, 900)]
    [int]$SamplingSeconds = 60,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = "C:\ProgramData\NinjaRMM-Diagnostics",

    [Parameter()]
    [switch]$ExtensiveTest
)

$ErrorActionPreference = "Stop"

if ($env:LookbackHours -and $env:LookbackHours -notlike "null") {
    $parsedLookbackHours = 0
    if (-not [int]::TryParse($env:LookbackHours, [ref]$parsedLookbackHours) -or $parsedLookbackHours -lt 1 -or $parsedLookbackHours -gt 8760) {
        Write-Error "LookbackHours must be a whole number from 1 through 8760. Received '$($env:LookbackHours)'."
        exit 1
    }
    $LookbackHours = $parsedLookbackHours
}

if ($env:SamplingSeconds -and $env:SamplingSeconds -notlike "null") {
    $parsedSamplingSeconds = 0
    if (-not [int]::TryParse($env:SamplingSeconds, [ref]$parsedSamplingSeconds) -or $parsedSamplingSeconds -lt 1 -or $parsedSamplingSeconds -gt 900) {
        Write-Error "SamplingSeconds must be a whole number from 1 through 900. Received '$($env:SamplingSeconds)'."
        exit 1
    }
    $SamplingSeconds = $parsedSamplingSeconds
}

if ($env:OutputDirectory -and $env:OutputDirectory -notlike "null") {
    $OutputDirectory = $env:OutputDirectory
}

if ($env:ExtensiveTest -and $env:ExtensiveTest -notlike "null") {
    $ExtensiveTest = $env:ExtensiveTest -match '^(?i:true|1|yes|on)$'
}

function Test-IsElevated {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-DiagnosticText {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $sanitizedText = $Text.Replace([string][char]0, "")
    $utf8Encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $sanitizedText, $utf8Encoding)
}

function Invoke-DiagnosticCollection {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Collection
    )

    $filePath = Join-Path -Path $script:CollectionDirectory -ChildPath $FileName
    Write-Host "Collecting $Name..."

    try {
        $result = & $Collection
        if ($null -eq $result) {
            Write-DiagnosticText -Path $filePath -Text "No data returned.`r`n"
        } else {
            $text = $result | Out-String -Width 4096
            Write-DiagnosticText -Path $filePath -Text $text
        }
    } catch {
        $message = "Failed to collect $Name. $($_.Exception.Message)"
        Write-DiagnosticText -Path $filePath -Text "$message`r`n"
        Write-Warning $message
    }
}

function Get-EventLogReport {
    param (
        [Parameter(Mandatory = $true)]
        [string]$LogName,

        [Parameter(Mandatory = $true)]
        [datetime]$StartTime
    )

    $events = Get-WinEvent -FilterHashtable @{
        LogName   = $LogName
        StartTime = $StartTime
        Level     = 1, 2, 3
    } -ErrorAction SilentlyContinue

    if (-not $events) {
        return "No critical, error, or warning events found in $LogName since $StartTime."
    }

    $suppressedEvents = $events | Where-Object { $_.ProviderName -eq "Microsoft-Windows-DistributedCOM" -and $_.Id -eq 10016 }
    $reportedEvents = $events | Where-Object { -not ($_.ProviderName -eq "Microsoft-Windows-DistributedCOM" -and $_.Id -eq 10016) }

    "=== EVENT SUMMARY ==="
    $reportedEvents | Group-Object -Property Level, ProviderName, Id | ForEach-Object {
        [PSCustomObject]@{
            Count     = $_.Count
            Level     = switch ($_.Group[0].Level) {
                1 { "Critical" }
                2 { "Error" }
                3 { "Warning" }
                default { "Level $($_.Group[0].Level)" }
            }
            Provider  = $_.Group[0].ProviderName
            EventId   = $_.Group[0].Id
            Latest    = ($_.Group | Sort-Object -Property TimeCreated -Descending | Select-Object -First 1).TimeCreated
        }
    } | Sort-Object -Property Count -Descending | Format-Table -AutoSize
    "=== SUPPRESSED NOISE ==="
    "Suppressed $($suppressedEvents.Count) DistributedCOM event 10016 entries from the detailed report."
    "=== EVENT DETAILS ==="
    $reportedEvents | Select-Object TimeCreated, Id, Level, ProviderName, MachineName, Message | Format-List
}

$startTime = (Get-Date).AddHours(-$LookbackHours)
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$computerName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "Windows-PC" }
$collectionName = "Diagnostics-$computerName-$timestamp"
$CollectionDirectory = Join-Path -Path $OutputDirectory -ChildPath $collectionName
$zipPath = Join-Path -Path $OutputDirectory -ChildPath "$collectionName.zip"
$transcriptStarted = $false

try {
    New-Item -Path $CollectionDirectory -ItemType Directory -Force | Out-Null
    Start-Transcript -Path (Join-Path -Path $CollectionDirectory -ChildPath "Collection.log") -Force | Out-Null
    $transcriptStarted = $true

    Write-Host "Collecting diagnostics for $computerName from $startTime through $(Get-Date)."
    Write-Host "Working directory: $CollectionDirectory"

    if (-not (Test-IsElevated)) {
        Write-Warning "The script is not running as an administrator. Some results may be incomplete."
    }

    Invoke-DiagnosticCollection -Name "collection summary" -FileName "Summary.txt" -Collection {
        [PSCustomObject]@{
            ComputerName        = $computerName
            CollectionStarted   = Get-Date
            LookbackHours       = $LookbackHours
            SamplingSeconds     = $SamplingSeconds
            DataStartTime       = $startTime
            PowerShellVersion   = $PSVersionTable.PSVersion.ToString()
            RunningAsUser       = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            RunningAsAdmin      = Test-IsElevated
            ExtensiveTest       = [bool]$ExtensiveTest
        } | Format-List
    }

    Invoke-DiagnosticCollection -Name "operating system and hardware" -FileName "System.txt" -Collection {
        "=== OPERATING SYSTEM ==="
        Get-CimInstance -ClassName Win32_OperatingSystem |
            Select-Object Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime, LocalDateTime, FreePhysicalMemory, TotalVisibleMemorySize |
            Format-List
        "=== COMPUTER SYSTEM ==="
        Get-CimInstance -ClassName Win32_ComputerSystem |
            Select-Object Manufacturer, Model, SystemType, Domain, PartOfDomain, TotalPhysicalMemory, NumberOfProcessors, NumberOfLogicalProcessors |
            Format-List
        "=== BIOS ==="
        Get-CimInstance -ClassName Win32_BIOS |
            Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate, SerialNumber |
            Format-List
        "=== PROCESSORS ==="
        Get-CimInstance -ClassName Win32_Processor |
            Select-Object Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, Status |
            Format-Table -AutoSize
        "=== PAGEFILE CONFIGURATION ==="
        Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue |
            Select-Object Name, InitialSize, MaximumSize |
            Format-Table -AutoSize
        "=== PAGEFILE USAGE ==="
        Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue |
            Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage, TempPageFile |
            Format-Table -AutoSize
    }

    Invoke-DiagnosticCollection -Name "storage" -FileName "Storage.txt" -Collection {
        "=== LOGICAL DISKS ==="
        Get-CimInstance -ClassName Win32_LogicalDisk |
            Select-Object DeviceID, VolumeName, FileSystem, DriveType, Size, FreeSpace, Status |
            Format-Table -AutoSize
        "=== PHYSICAL DISKS ==="
        Get-CimInstance -ClassName Win32_DiskDrive |
            Select-Object Index, DeviceID, Model, SerialNumber, InterfaceType, MediaType, Size, Status |
            Format-Table -AutoSize
        "=== STORAGE DISKS ==="
        Get-Disk | Sort-Object -Property Number |
            Select-Object Number, FriendlyName, SerialNumber, BusType, OperationalStatus, HealthStatus, PartitionStyle, Size, IsBoot, IsSystem |
            Format-Table -AutoSize
        "=== PARTITION TO DISK MAPPING ==="
        Get-Partition | Sort-Object -Property DiskNumber, PartitionNumber |
            Select-Object DiskNumber, PartitionNumber, DriveLetter, Type, Size, IsBoot, IsSystem, IsReadOnly, IsOffline |
            Format-Table -AutoSize
        "=== STORAGE RELIABILITY COUNTERS ==="
        Get-PhysicalDisk | ForEach-Object {
            $physicalDisk = $_
            try {
                $reliability = $physicalDisk | Get-StorageReliabilityCounter -ErrorAction Stop
                [PSCustomObject]@{
                    DeviceId                = $physicalDisk.DeviceId
                    FriendlyName            = $physicalDisk.FriendlyName
                    TemperatureCelsius      = $reliability.Temperature
                    TemperatureMaxCelsius   = $reliability.TemperatureMax
                    WearPercent             = $reliability.Wear
                    PowerOnHours            = $reliability.PowerOnHours
                    ReadErrorsTotal         = $reliability.ReadErrorsTotal
                    ReadErrorsUncorrected   = $reliability.ReadErrorsUncorrected
                    WriteErrorsTotal        = $reliability.WriteErrorsTotal
                    WriteErrorsUncorrected  = $reliability.WriteErrorsUncorrected
                }
            } catch {
                [PSCustomObject]@{
                    DeviceId                = $physicalDisk.DeviceId
                    FriendlyName            = $physicalDisk.FriendlyName
                    TemperatureCelsius      = $null
                    TemperatureMaxCelsius   = $null
                    WearPercent             = $null
                    PowerOnHours            = $null
                    ReadErrorsTotal         = "Unavailable: $($_.Exception.Message)"
                    ReadErrorsUncorrected   = $null
                    WriteErrorsTotal        = $null
                    WriteErrorsUncorrected  = $null
                }
            }
        } | Format-Table -AutoSize
    }

    Invoke-DiagnosticCollection -Name "battery, thermal, and power state" -FileName "Power-Battery.txt" -Collection {
        $batteryHtmlPath = Join-Path -Path $script:CollectionDirectory -ChildPath "Battery-Report.html"
        $batteryXmlPath = Join-Path -Path $script:CollectionDirectory -ChildPath "Battery-Report.xml"

        "=== ACTIVE POWER PLAN ==="
        & powercfg.exe /GETACTIVESCHEME
        "=== AVAILABLE SLEEP STATES ==="
        & powercfg.exe /AVAILABLESLEEPSTATES
        "=== BATTERY REPORT GENERATION ==="
        & powercfg.exe /BATTERYREPORT /OUTPUT $batteryHtmlPath
        & powercfg.exe /BATTERYREPORT /XML /OUTPUT $batteryXmlPath
        "=== BATTERY STATUS ==="
        $batteries = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
        if ($batteries) {
            $batteries | Select-Object Name, DeviceID, Status, BatteryStatus, EstimatedChargeRemaining, EstimatedRunTime, DesignVoltage |
                Format-List
        } else {
            "No battery was reported by Win32_Battery."
        }
        "=== BATTERY CAPACITY ==="
        $batteryCapacity = @()
        if (Test-Path -LiteralPath $batteryXmlPath) {
            try {
                [xml]$batteryReport = Get-Content -LiteralPath $batteryXmlPath -Raw -ErrorAction Stop
                $batteryCapacity = @($batteryReport.SelectNodes("//*[local-name()='Batteries']/*[local-name()='Battery']") | ForEach-Object {
                    $nameNode = $_.SelectSingleNode("./*[local-name()='Id']")
                    if (-not $nameNode) {
                        $nameNode = $_.SelectSingleNode("./*[local-name()='Name']")
                    }
                    $designCapacityNode = $_.SelectSingleNode("./*[local-name()='DesignCapacity']")
                    $fullChargeCapacityNode = $_.SelectSingleNode("./*[local-name()='FullChargeCapacity']")
                    $cycleCountNode = $_.SelectSingleNode("./*[local-name()='CycleCount']")
                    $designedCapacity = if ($designCapacityNode) { [double]$designCapacityNode.InnerText } else { 0 }
                    $fullChargedCapacity = if ($fullChargeCapacityNode) { [double]$fullChargeCapacityNode.InnerText } else { 0 }

                    [PSCustomObject]@{
                        Name                   = if ($nameNode) { $nameNode.InnerText } else { "Battery" }
                        DesignedCapacityMWh    = $designedCapacity
                        FullChargedCapacityMWh = $fullChargedCapacity
                        HealthPercent          = if ($designedCapacity -gt 0) {
                            [Math]::Round(($fullChargedCapacity / $designedCapacity) * 100, 1)
                        } else { $null }
                        CycleCount             = if ($cycleCountNode) { $cycleCountNode.InnerText } else { $null }
                        Source                 = "powercfg XML"
                    }
                })
            } catch {
                Write-Warning "Unable to parse the powercfg battery XML report. $($_.Exception.Message)"
            }
        }

        if (-not $batteryCapacity) {
            $staticBatteries = @(Get-CimInstance -Namespace "root/wmi" -ClassName BatteryStaticData -ErrorAction SilentlyContinue)
            $fullChargeBatteries = @(Get-CimInstance -Namespace "root/wmi" -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue)
            $batteryCapacity = @(for ($index = 0; $index -lt $staticBatteries.Count; $index++) {
                $battery = $staticBatteries[$index]
                $fullCharge = $fullChargeBatteries | Where-Object { $_.InstanceName -eq $battery.InstanceName } | Select-Object -First 1
                if (-not $fullCharge -and $index -lt $fullChargeBatteries.Count) {
                    $fullCharge = $fullChargeBatteries[$index]
                }
                [PSCustomObject]@{
                    Name                   = $battery.InstanceName
                    DesignedCapacityMWh    = $battery.DesignedCapacity
                    FullChargedCapacityMWh = $fullCharge.FullChargedCapacity
                    HealthPercent          = if ($battery.DesignedCapacity -gt 0 -and $fullCharge) {
                        [Math]::Round(($fullCharge.FullChargedCapacity / $battery.DesignedCapacity) * 100, 1)
                    } else { $null }
                    CycleCount             = $null
                    Source                 = "WMI"
                }
            })
        }

        if ($batteryCapacity) {
            $batteryCapacity | Format-Table -AutoSize
        } else {
            "Battery capacity data is unavailable."
        }
        "=== ACPI THERMAL ZONES ==="
        $thermalZones = Get-CimInstance -Namespace "root/wmi" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        if ($thermalZones) {
            $thermalZones | Select-Object InstanceName, @{ Name = "CurrentCelsius"; Expression = { [Math]::Round(($_.CurrentTemperature / 10) - 273.15, 1) } } |
                Format-Table -AutoSize
        } else {
            "ACPI thermal zone data is unavailable."
        }
    }

    Invoke-DiagnosticCollection -Name "network configuration" -FileName "Network.txt" -Collection {
        "=== IP CONFIGURATION ==="
        Get-NetIPConfiguration -Detailed | Format-List
        "=== NETWORK ADAPTERS ==="
        Get-NetAdapter | Sort-Object -Property Name |
            Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress, DriverVersion |
            Format-Table -AutoSize
        "=== ROUTES ==="
        Get-NetRoute | Sort-Object -Property InterfaceIndex, DestinationPrefix |
            Select-Object InterfaceIndex, DestinationPrefix, NextHop, RouteMetric, State |
            Format-Table -AutoSize
        "=== DNS CLIENT SERVERS ==="
        Get-DnsClientServerAddress | Format-Table -AutoSize
        "=== TCP CONNECTIONS ==="
        Get-NetTCPConnection | Sort-Object -Property State, RemoteAddress |
            Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess |
            Format-Table -AutoSize
    }

    Invoke-DiagnosticCollection -Name "wireless network report" -FileName "Wlan-Report.txt" -Collection {
        $wlanReportSource = Join-Path -Path $env:ProgramData -ChildPath "Microsoft\Windows\WlanReport"
        $wlanReportDestination = Join-Path -Path $script:CollectionDirectory -ChildPath "WlanReport"
        & netsh.exe wlan show wlanreport 2>&1
        if (Test-Path -LiteralPath $wlanReportSource) {
            New-Item -Path $wlanReportDestination -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path -Path $wlanReportSource -ChildPath "*") -Destination $wlanReportDestination -Recurse -Force -ErrorAction Stop
            "Copied WLAN report files to WlanReport."
        } else {
            "WLAN report directory was not created. The computer may not have an enabled WLAN adapter."
        }
    }

    Invoke-DiagnosticCollection -Name "sampled performance" -FileName "Performance.txt" -Collection {
        $counterPaths = @(
            "\Processor(_Total)\% Processor Time",
            "\Processor(_Total)\% DPC Time",
            "\Processor(_Total)\% Interrupt Time",
            "\Processor(_Total)\DPC Rate",
            "\Processor(_Total)\Interrupts/sec",
            "\System\Processor Queue Length",
            "\Memory\Available MBytes",
            "\Memory\% Committed Bytes In Use",
            "\Memory\Pages/sec",
            "\Memory\Page Reads/sec",
            "\PhysicalDisk(_Total)\Avg. Disk sec/Transfer",
            "\PhysicalDisk(_Total)\Current Disk Queue Length",
            "\PhysicalDisk(_Total)\Disk Bytes/sec"
        )
        if ($ExtensiveTest) {
            $counterPaths += @(
                "\Processor(*)\% Processor Time",
                "\Processor(*)\% DPC Time",
                "\Processor(*)\% Interrupt Time"
            )
        }
        $logicalProcessorCount = [Environment]::ProcessorCount
        $sampleStarted = Get-Date
        $initialProcesses = @{}
        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            $initialProcesses[$_.Id] = $_.CPU
        }

        $wprStarted = $false
        $wprPath = Join-Path -Path $script:CollectionDirectory -ChildPath "CPU-Trace.etl"
        if ($ExtensiveTest) {
            try {
                & wpr.exe -start CPU -filemode 2>&1 | Out-String | Write-Host
                if ($LASTEXITCODE -eq 0) {
                    $wprStarted = $true
                } else {
                    Write-Warning "WPR did not start; exit code $LASTEXITCODE."
                }
            } catch {
                Write-Warning "WPR CPU trace could not be started. $($_.Exception.Message)"
            }
        }

        try {
            $counterData = Get-Counter -Counter $counterPaths -SampleInterval 1 -MaxSamples ($SamplingSeconds + 1)
        } finally {
            if ($wprStarted) {
                try {
                    & wpr.exe -stop $wprPath "NinjaOne extensive CPU diagnostic" 2>&1 | Out-String | Write-Host
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "WPR stop returned exit code $LASTEXITCODE."
                        & wpr.exe -cancel 2>&1 | Out-Null
                    }
                } catch {
                    Write-Warning "WPR trace could not be saved. $($_.Exception.Message)"
                    & wpr.exe -cancel 2>&1 | Out-Null
                }
            }
        }
        $sampleEnded = Get-Date
        $actualSamplingSeconds = ($sampleEnded - $sampleStarted).TotalSeconds
        $finalProcesses = Get-Process -ErrorAction SilentlyContinue

        $script:ProcessPerformance = $finalProcesses | ForEach-Object {
            $cpuPercent = $null
            $processStartTime = try { $_.StartTime } catch { $null }
            $processPath = try { $_.Path } catch { $null }
            if ($initialProcesses.ContainsKey($_.Id) -and $null -ne $_.CPU -and $null -ne $initialProcesses[$_.Id]) {
                $cpuSeconds = $_.CPU - $initialProcesses[$_.Id]
                $cpuPercent = ($cpuSeconds / $actualSamplingSeconds / $logicalProcessorCount) * 100
            }
            [PSCustomObject]@{
                Name                 = $_.Name
                Id                   = $_.Id
                SampledCPUPercent    = $cpuPercent
                WorkingSetBytes      = $_.WorkingSet64
                PrivateMemoryBytes   = $_.PrivateMemorySize64
                TotalCPUSeconds      = $_.CPU
                StartTime            = $processStartTime
                Path                 = $processPath
            }
        }

        $flatSamples = $counterData | ForEach-Object {
            $timestamp = $_.Timestamp
            $_.CounterSamples | ForEach-Object {
                [PSCustomObject]@{
                    Timestamp     = $timestamp
                    Counter       = $_.Path
                    CookedValue   = $_.CookedValue
                }
            }
        }
        $flatSamples | Export-Csv -Path (Join-Path -Path $script:CollectionDirectory -ChildPath "Performance-Samples.csv") -NoTypeInformation -Encoding UTF8

        "=== SAMPLE WINDOW ==="
        [PSCustomObject]@{
            RequestedSeconds = $SamplingSeconds
            ActualSeconds    = [Math]::Round($actualSamplingSeconds, 2)
            Started          = $sampleStarted
            Ended            = $sampleEnded
        } | Format-List
        "=== COUNTER SUMMARY ==="
        $script:PerformanceSummary = $flatSamples | Group-Object -Property Counter | ForEach-Object {
            $values = $_.Group.CookedValue | Measure-Object -Average -Minimum -Maximum
            [PSCustomObject]@{
                Counter = $_.Name
                Average = [Math]::Round($values.Average, 3)
                Minimum = [Math]::Round($values.Minimum, 3)
                Maximum = [Math]::Round($values.Maximum, 3)
            }
        }
        $script:PerformanceSummary | Format-Table -AutoSize
    }

    Invoke-DiagnosticCollection -Name "processes" -FileName "Processes.txt" -Collection {
        $processes = if ($script:ProcessPerformance) {
            $script:ProcessPerformance
        } else {
            Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
                $processStartTime = try { $_.StartTime } catch { $null }
                $processPath = try { $_.Path } catch { $null }
                [PSCustomObject]@{
                    Name                 = $_.Name
                    Id                   = $_.Id
                    SampledCPUPercent    = $null
                    WorkingSetBytes      = $_.WorkingSet64
                    PrivateMemoryBytes   = $_.PrivateMemorySize64
                    TotalCPUSeconds      = $_.CPU
                    StartTime            = $processStartTime
                    Path                 = $processPath
                }
            }
        }

        "=== PROCESSES BY SAMPLED CPU ==="
        $processes | Sort-Object -Property SampledCPUPercent -Descending |
            Format-Table -AutoSize
        "=== PROCESSES GROUPED BY NAME ==="
        $processes | Group-Object -Property Name | ForEach-Object {
            $cpu = $_.Group | Measure-Object -Property SampledCPUPercent -Sum
            $workingSet = $_.Group | Measure-Object -Property WorkingSetBytes -Sum
            $privateMemory = $_.Group | Measure-Object -Property PrivateMemoryBytes -Sum
            [PSCustomObject]@{
                Name               = $_.Name
                Count              = $_.Count
                SampledCPUPercent  = [Math]::Round($cpu.Sum, 2)
                WorkingSetBytes    = $workingSet.Sum
                PrivateMemoryBytes = $privateMemory.Sum
            }
        } | Sort-Object -Property WorkingSetBytes -Descending | Format-Table -AutoSize
    }

    Invoke-DiagnosticCollection -Name "services" -FileName "Services.txt" -Collection {
        Get-CimInstance -ClassName Win32_Service | Sort-Object -Property State, Name |
            Select-Object Name, DisplayName, State, StartMode, StartName, ExitCode, PathName |
            Format-Table -AutoSize
    }

    Invoke-DiagnosticCollection -Name "installed updates" -FileName "Updates.txt" -Collection {
        "=== INSTALLED HOTFIXES ==="
        Get-HotFix | Sort-Object -Property InstalledOn -Descending | Format-Table -AutoSize
        "=== WINDOWS UPDATE CLIENT EVENTS ==="
        Get-WinEvent -FilterHashtable @{
            LogName   = "System"
            StartTime = $startTime
            ProviderName = "Microsoft-Windows-WindowsUpdateClient"
        } -ErrorAction SilentlyContinue |
            Select-Object TimeCreated, Id, LevelDisplayName, Message |
            Format-List
    }

    Invoke-DiagnosticCollection -Name "security products" -FileName "Security.txt" -Collection {
        "=== REGISTERED ANTIVIRUS PRODUCTS ==="
        Get-CimInstance -Namespace "root/SecurityCenter2" -ClassName AntiVirusProduct |
            Select-Object displayName, productState, pathToSignedProductExe, timestamp |
            Format-Table -AutoSize
        "=== MICROSOFT DEFENDER STATUS ==="
        Get-MpComputerStatus | Format-List
        "=== FIREWALL PROFILES ==="
        Get-NetFirewallProfile | Format-Table -AutoSize
    }

    Invoke-DiagnosticCollection -Name "system event log" -FileName "Events-System.txt" -Collection {
        Get-EventLogReport -LogName "System" -StartTime $startTime
    }

    Invoke-DiagnosticCollection -Name "application event log" -FileName "Events-Application.txt" -Collection {
        Get-EventLogReport -LogName "Application" -StartTime $startTime
    }

    Invoke-DiagnosticCollection -Name "raw Windows event logs" -FileName "EventLog-Export.txt" -Collection {
        $eventLogDirectory = Join-Path -Path $script:CollectionDirectory -ChildPath "EventLogs"
        New-Item -Path $eventLogDirectory -ItemType Directory -Force | Out-Null
        $exports = @(
            @{ Log = "System"; File = "System.evtx" },
            @{ Log = "Application"; File = "Application.evtx" },
            @{ Log = "Microsoft-Windows-WLAN-AutoConfig/Operational"; File = "WLAN-AutoConfig-Operational.evtx" }
        )
        if ($ExtensiveTest) {
            $exports += @(
                @{ Log = "Microsoft-Windows-TaskScheduler/Operational"; File = "TaskScheduler-Operational.evtx" },
                @{ Log = "Microsoft-Windows-Kernel-PnP/Configuration"; File = "Kernel-PnP-Configuration.evtx" },
                @{ Log = "Microsoft-Windows-BitLocker/BitLocker Management"; File = "BitLocker-Management.evtx" },
                @{ Log = "Microsoft-Windows-BitLocker/BitLocker Operational"; File = "BitLocker-Operational.evtx" }
            )
        }
        foreach ($export in $exports) {
            $destination = Join-Path -Path $eventLogDirectory -ChildPath $export.File
            & wevtutil.exe epl $export.Log $destination /ow:true 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $destination)) {
                "Exported $($export.Log) to EventLogs\$($export.File)."
            } else {
                "Unable to export $($export.Log); exit code $LASTEXITCODE. The log may be disabled or unavailable."
            }
        }
    }

    Invoke-DiagnosticCollection -Name "reliability events" -FileName "Reliability.txt" -Collection {
        Get-CimInstance -ClassName Win32_ReliabilityRecords |
            Where-Object { $_.TimeGenerated -ge $startTime } |
            Sort-Object -Property TimeGenerated -Descending |
            Select-Object TimeGenerated, SourceName, EventIdentifier, ProductName, Message |
            Format-List
    }

    Invoke-DiagnosticCollection -Name "recent crash dumps" -FileName "Crash-Dumps.txt" -Collection {
        $dumpLocations = @(
            "$env:SystemRoot\Minidump",
            "$env:SystemRoot\MEMORY.DMP",
            "$env:LOCALAPPDATA\CrashDumps"
        )
        Get-ChildItem -Path $dumpLocations -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $startTime } |
            Select-Object FullName, Length, CreationTime, LastWriteTime |
            Format-Table -AutoSize
    }

    Invoke-DiagnosticCollection -Name "diagnostic findings" -FileName "Findings.txt" -Collection {
        $findings = [System.Collections.Generic.List[object]]::new()
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
        $availableMemoryPercent = ($operatingSystem.FreePhysicalMemory / $operatingSystem.TotalVisibleMemorySize) * 100
        if ($availableMemoryPercent -lt 5) {
            $findings.Add([PSCustomObject]@{ Severity = "High"; Area = "Memory"; Finding = "Only $([Math]::Round($availableMemoryPercent, 1))% of physical memory is currently free." })
        } elseif ($availableMemoryPercent -lt 10) {
            $findings.Add([PSCustomObject]@{ Severity = "Medium"; Area = "Memory"; Finding = "Only $([Math]::Round($availableMemoryPercent, 1))% of physical memory is currently free." })
        }

        Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" | ForEach-Object {
            if ($_.Size -gt 0) {
                $freePercent = ($_.FreeSpace / $_.Size) * 100
                if ($freePercent -lt 10) {
                    $findings.Add([PSCustomObject]@{ Severity = "High"; Area = "Storage"; Finding = "Drive $($_.DeviceID) has only $([Math]::Round($freePercent, 1))% free space." })
                } elseif ($freePercent -lt 15) {
                    $findings.Add([PSCustomObject]@{ Severity = "Medium"; Area = "Storage"; Finding = "Drive $($_.DeviceID) has only $([Math]::Round($freePercent, 1))% free space." })
                }
            }
        }

        if ($script:PerformanceSummary) {
            $cpuCounter = $script:PerformanceSummary | Where-Object { $_.Counter -like "*\Processor(_Total)\% Processor Time" } | Select-Object -First 1
            $memoryCounter = $script:PerformanceSummary | Where-Object { $_.Counter -like "*\Memory\Available MBytes" } | Select-Object -First 1
            $commitCounter = $script:PerformanceSummary | Where-Object { $_.Counter -like "*\Memory\% Committed Bytes In Use" } | Select-Object -First 1
            $diskLatencyCounter = $script:PerformanceSummary | Where-Object { $_.Counter -like "*\PhysicalDisk(_Total)\Avg. Disk sec/Transfer" } | Select-Object -First 1

            if ($cpuCounter.Average -ge 85) {
                $findings.Add([PSCustomObject]@{ Severity = "High"; Area = "CPU"; Finding = "Average CPU utilization was $($cpuCounter.Average)% during the sample." })
            }
            if ($memoryCounter.Minimum -lt 512) {
                $findings.Add([PSCustomObject]@{ Severity = "High"; Area = "Memory"; Finding = "Available memory fell to $([Math]::Round($memoryCounter.Minimum)) MB during the sample." })
            } elseif ($memoryCounter.Minimum -lt 1024) {
                $findings.Add([PSCustomObject]@{ Severity = "Medium"; Area = "Memory"; Finding = "Available memory fell to $([Math]::Round($memoryCounter.Minimum)) MB during the sample." })
            }
            if ($commitCounter.Maximum -ge 90) {
                $findings.Add([PSCustomObject]@{ Severity = "High"; Area = "Memory"; Finding = "Committed memory reached $($commitCounter.Maximum)% during the sample." })
            }
            if ($diskLatencyCounter.Average -ge 0.05) {
                $findings.Add([PSCustomObject]@{ Severity = "Medium"; Area = "Storage"; Finding = "Average disk transfer latency was $([Math]::Round($diskLatencyCounter.Average * 1000, 1)) ms during the sample." })
            }
        } else {
            $findings.Add([PSCustomObject]@{ Severity = "Info"; Area = "Performance"; Finding = "Sampled performance counters were unavailable; review Performance.txt for the collection error." })
        }

        $eventLogs = @("System", "Application")
        $events = foreach ($eventLog in $eventLogs) {
            Get-WinEvent -FilterHashtable @{ LogName = $eventLog; StartTime = $startTime; Level = 1, 2, 3 } -ErrorAction SilentlyContinue
        }
        $actionableEvents = $events | Where-Object { -not ($_.ProviderName -eq "Microsoft-Windows-DistributedCOM" -and $_.Id -eq 10016) }
        $storageEvents = $actionableEvents | Where-Object {
            $_.ProviderName -match "^(disk|Ntfs|exfat|stornvme|storahci)$" -or $_.Id -in 51, 55, 129, 141, 153, 157
        }
        if ($storageEvents) {
            $findings.Add([PSCustomObject]@{ Severity = "High"; Area = "Storage"; Finding = "$($storageEvents.Count) storage warning or error events were recorded during the lookback period." })
        }
        $hardwareEvents = $actionableEvents | Where-Object { $_.ProviderName -eq "Microsoft-Windows-WHEA-Logger" }
        if ($hardwareEvents) {
            $findings.Add([PSCustomObject]@{ Severity = "High"; Area = "Hardware"; Finding = "$($hardwareEvents.Count) WHEA hardware events were recorded during the lookback period." })
        }
        $resourceEvents = $actionableEvents | Where-Object { $_.ProviderName -eq "Microsoft-Windows-Resource-Exhaustion-Detector" -or $_.Id -eq 2004 }
        if ($resourceEvents) {
            $findings.Add([PSCustomObject]@{ Severity = "High"; Area = "Memory"; Finding = "$($resourceEvents.Count) resource exhaustion events were recorded during the lookback period." })
        }
        $applicationCrashes = $actionableEvents | Where-Object { $_.ProviderName -in "Application Error", "Application Hang" -and $_.Id -in 1000, 1002 }
        if ($applicationCrashes) {
            $findings.Add([PSCustomObject]@{ Severity = "Medium"; Area = "Applications"; Finding = "$($applicationCrashes.Count) application crash or hang events were recorded during the lookback period." })
        }

        "=== AUTOMATED FINDINGS ==="
        if ($findings.Count -eq 0) {
            "No threshold-based findings were identified. This does not guarantee that the system is healthy."
        } else {
            $severityOrder = @{ High = 1; Medium = 2; Info = 3 }
            $findings | Sort-Object -Property @{ Expression = { $severityOrder[$_.Severity] } }, Area | Format-Table -AutoSize -Wrap
        }
        "=== EVENT SIGNATURES (DCOM 10016 EXCLUDED) ==="
        $actionableEvents | Group-Object -Property Level, ProviderName, Id | ForEach-Object {
            [PSCustomObject]@{
                Count    = $_.Count
                Level    = switch ($_.Group[0].Level) {
                    1 { "Critical" }
                    2 { "Error" }
                    3 { "Warning" }
                    default { "Level $($_.Group[0].Level)" }
                }
                Provider = $_.Group[0].ProviderName
                EventId  = $_.Group[0].Id
                Latest   = ($_.Group | Sort-Object -Property TimeCreated -Descending | Select-Object -First 1).TimeCreated
            }
        } | Sort-Object -Property Count -Descending | Select-Object -First 25 | Format-Table -AutoSize
        "Suppressed DCOM 10016 count: $(($events | Where-Object { $_.ProviderName -eq "Microsoft-Windows-DistributedCOM" -and $_.Id -eq 10016 }).Count)"
    }
} catch {
    Write-Error "Diagnostic collection failed. $($_.Exception.Message)"
    exit 1
} finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}

try {
    Compress-Archive -Path (Join-Path -Path $CollectionDirectory -ChildPath "*") -DestinationPath $zipPath -CompressionLevel Optimal -Force
    Remove-Item -Path $CollectionDirectory -Recurse -Force
    Write-Host "Diagnostic collection completed successfully."
    Write-Host "Archive: $zipPath"
    exit 0
} catch {
    Write-Error "Diagnostics were collected in '$CollectionDirectory', but the ZIP archive could not be created. $($_.Exception.Message)"
    exit 1
}
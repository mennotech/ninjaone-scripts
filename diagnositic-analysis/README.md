# About

Diagnostic bundles collected from devices by [122-Collect Windows Diagnostics.ps1](../Windows/Powershell/122-Collect%20Windows%20Diagnostics.ps1), kept here so an agent or analyst can review them for problems and suspicious behaviour.

## Contents

- `Diagnostics-<COMPUTER>-<yyyyMMdd-HHmmss>/`: one extracted bundle per collection run.
- Supporting evidence from other tools, such as NinjaOne activity exports (`Activities-export-*.csv`) and SentinelOne threat details. Add these next to the bundle they relate to.


## Collecting a bundle

1. Run the script from NinjaOne (or locally as administrator). It writes to `C:\ProgramData\NinjaRMM-Diagnostics` and creates a ZIP.
2. Set `LookbackHours` to cover the period of interest (for example `1440` for 60 days).
3. Copy the ZIP off the device and extract it here.

Security-related event logs are exported by default. Set `DisableSecurityLogs` to `true` to skip them. Bundles can contain account names, process paths, and other sensitive data, so restrict access and delete them when the investigation ends.

## Bundle layout

| File or folder | Description |
|---|---|
| `Summary.txt` | Collection time, lookback window, account used |
| `Findings.txt` | Threshold-based findings and the most frequent event signatures |
| `Events-System.txt`, `Events-Application.txt` | Critical, error, and warning events within the lookback window |
| `EventLogs/*.evtx` | Raw logs: System, Application, WLAN, Security, PowerShell, Task Scheduler, and Defender (plus Sysmon if installed) |
| `EventLog-Export.txt` | Export result for each raw log |
| `Reliability.txt` | Windows Installer and reliability records, including install and removal results |
| `Security.txt` | Registered antivirus products, Defender status, firewall profiles |
| `Services.txt`, `Processes.txt` | Service configuration and running processes at collection time |
| `System.txt`, `Storage.txt`, `Network.txt`, `Updates.txt` | Hardware, disk, network, and patch information |
| `Performance*.txt`, `Performance-Samples.csv` | Sampled performance counters |
| `Power-Battery.txt`, `Battery-Report.*`, `Wlan-Report.txt`, `WlanReport/` | Power and Wi-Fi reports |
| `Crash-Dumps.txt` | Recent crash dump files |

## Limits to check before drawing conclusions

- **Retention varies by log.** Windows overwrites old events, so the lookback window can be longer than what survives. Check the oldest event in each `.evtx` before concluding that nothing happened. The Security and PowerShell logs often hold only days.
- **The text reports contain only warnings and errors.** Service changes, installs, and logons are informational events that appear only in the raw `.evtx` files.
- **Process command lines are not recorded** unless command-line auditing is enabled, so process-creation events show the program but not its arguments.
- **Timestamps.** Bundle files use the device's local time. NinjaOne and SentinelOne exports use UTC. Convert before comparing.
- **The collection itself leaves entries** in the PowerShell and Security logs; ignore events at the collection time.

## Reading event logs

The raw logs can be queried without touching the live system:

```powershell
Get-WinEvent -FilterHashtable @{ Path = '.\Diagnostics-<name>\EventLogs\System.evtx'; Id = 7045, 7040 }
```

Useful starting points:

| Question | Log and event ID |
|---|---|
| Was a service installed or changed? | System 7045, 7040; Security 4697 |
| Did a program install, fail, or uninstall? | Application, source `MsiInstaller` (1033, 1034, 11729, 11730) |
| Was a scheduled task added or changed? | Security 4698 to 4701; Task Scheduler 106, 140, 141 |
| Was a log cleared? | System 104; Security 1102 |
| Who logged on? | Security 4624, 4625, 4648, 4672 |
| What was run? | Security 4688 |

## Example Prompts

- Review the latest bundle for suspicious behaviour around `<date>`. List what each log covers, what you checked, and what you could not check.
- Compare the SentinelOne threat details with the bundle's events at the detection time. Convert UTC to local time first.
- Explain why the NinjaOne agent failed to install or update, using the Windows Installer events and the NinjaOne activity export.
- Check `Findings.txt` for false positives by confirming each finding against the raw event logs.


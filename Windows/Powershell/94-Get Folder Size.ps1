# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Get Folder Size
# ==============================================================================
#
# Description:
#   Returns the entire space used by all subfolders in the RootFolder specified
#
# Metadata:
#   - NinjaOne Script ID: 94
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2025-05-31
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-06-18 22:28:37
#   - Active: True
# Script Variables (NinjaOne):
#   - rootfolder (TEXT, Required): The root folder to scan, a list of subfolders and their sizes will be returned.
#     Default: Default
#   - recurse (CHECKBOX, Optional): Determines whether or not a recursive search is done
#     Default: true
#
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
<#
.SYNOPSIS
    This script scans a specified folder and its subfolders, calculating the size of each subfolder and displaying the results in a table format.
    
.DESCRIPTION
    This script returns a listing of subfolders and their size. If RootFolder is set to "Default", then it scans the root drive, and the following folders
        \Users
        \ProgramData
        \Program Files
        \Program Files (x86)
    The script can be run with the following parameters:
        -RootFolder: Specifies the root folder to scan. Default is "Default", which scans the system drive and common folders.
        -Recurse: Specifies whether to scan subfolders recursively. Default is $true.
    Note:
      - by default a recursive search will be done and can take a long time to run
      - "CloudOnly" files are not counted (gci -Attribute !o is used)

.EXAMPLE
    -RootFolder "C:\Windows" -Recurse $false

Scanning C:\Windows\

        Size         Items  Folder
        ----         -----  ------
     14.0 GB          3708  C:\Windows\Temp
     10.8 GB           197  C:\Windows\Installer
      2.4 GB          4703  C:\Windows\System32
    946.8 MB          2809  C:\Windows\SysWOW64
    945.4 MB           128  C:\Windows\SystemTemp
    380.7 MB           538  C:\Windows\Fonts
    149.7 MB           144  C:\Windows\SystemResources
    118.4 MB            77  C:\Windows\Panther
    104.6 MB          1545  C:\Windows\INF
     24.3 MB             1  C:\Windows\Containers
     22.4 MB             1  C:\Windows\{27842841-FE98-4D46-9DB2-D744F4F58688}
     21.9 MB             1  C:\Windows\{07D3B026-7774-4BC0-84FF-C71E5BAE9EC5}
     20.2 MB            85  C:\Windows\Media
     15.8 MB            29  C:\Windows\
     15.3 MB            12  C:\Windows\ShellExperiences
     13.9 MB           385  C:\Windows\Prefetch
     11.0 MB           206  C:\Windows\Cursors
     10.9 MB             9  C:\Windows\ImmersiveControlPanel
      9.5 MB             8  C:\Windows\apppatch

.OUTPUTS
    Outputs a table with the size, number of items, and folder path for each scanned folder.

.NOTES
    2025-06-18: Initial version of the script.
    
.LINK
    https://github.com/mennotech/rmm-scripts/blob/main/powershell/Get-Folder-Size.ps1

.LICENSE
    This script is released under the MIT License.
#>


Param(
    [string] $RootFolder = "Default",
    [bool] $Recurse = $true
)

# Replace parameters with dynamic script variables.
if ($env:RootFolder -and $env:RootFolder -notlike "null") { $RootFolder = $env:RootFolder }
if ($env:Recurse -and $env:Recurse -eq "false") { $Recurse = $false }

Function Main {
    #By default scan C:\ and then C:\Users
    if ($rootFolder -eq "Default") {
        $results = Scan-Folder -RootFolder "$($Env:SystemDrive)\" -Recurse $Recurse
        Write-FolderTable $results

        $results = Scan-Folder -RootFolder "$($Env:SystemDrive)\Users" -Recurse $Recurse
        Write-FolderTable $results

        $results = Scan-Folder -RootFolder $Env:ProgramData -Recurse $Recurse
        Write-FolderTable $results

        $results = Scan-Folder -RootFolder $Env:ProgramFiles -Recurse $Recurse
        Write-FolderTable $results
        
        $results = Scan-Folder -RootFolder ${Env:ProgramFiles(x86)} -Recurse $Recurse
        Write-FolderTable $results
        
        

    } else {
        if (!(Test-Path -Path $RootFolder)) {
           Write-Error "$RootFolder does not exist. Exiting"
            Exit 100
        }
        
        $results = Scan-Folder -RootFolder $RootFolder -Recurse $Recurse
        Write-FolderTable $results
    }

}

Function Write-FolderTable {
    Param(
        [object] $table,
        [string] $sortBy = 'Size'
    )
    
    $sorted = $table | Sort-Object -Descending -Property $SortBy
    
    Write-Host ""
    Write-Host "        Size         Items  Folder"
    Write-Host "        ----         -----  ------"
    
    foreach($row in $sorted) {
        Write-Host "$((Format-Bytes $row.Size).PadLeft(12,' '))  $(([string]$row.FilesCount).PadLeft(12,' '))  $($row.Folder)"
    }
    Write-Host ""

}


Function Scan-Folder {
    Param(
        [string] $RootFolder,
        [bool] $Recurse = $true
    )

    #Remove previous all jobs
    Get-Job | Remove-Job

    #Set Max Threads
    $MaxThreads = 20

    #Initialize Results variable
    $Results = @()

    #Get a list of sub folders
    $Folders = Get-ChildItem -Path $RootFolder -Directory -Force
    $FolderCount = $Folders.Count + 1
    

    Write-Host "Scanning $RootFolder"

    #Start the jobs. 

    #Scan Root Folder
    $null = Start-Job -Scriptblock (Get-JobBlock) -ArgumentList $RootFolder,$false

    #Scan subfolders
    foreach($Folder in $Folders.FullName){
        $x += 1
        While ($(Get-Job -state running).count -ge $MaxThreads){
            Start-Sleep -Seconds 1
        }    
        $null = Start-Job -Scriptblock (Get-JobBlock) -ArgumentList $Folder,$Recurse
        $completedjobs = (Get-Job -state Completed).count
        Write-Progress -Activity "Scanning folders... ($completedjobs of $FolderCount)" -CurrentOperation "$($x)" -PercentComplete (($completedjobs / $FolderCount) * 100)
    }


    #Wait for all jobs to finish.
    While ((Get-Job -State Running).count -gt 0){
        $i += 1
        $completedjobs = (Get-Job -state Completed).count
        Write-Progress -Activity "Scanning folders... ($completedjobs of $FolderCount)" -CurrentOperation "$($i + $x)" -PercentComplete (($completedjobs / $FolderCount) * 100)
        start-sleep 1
    }

    #Get Root Folder Size



    #Get information from each job.
    foreach($job in Get-Job){
        $results += Receive-Job -Id ($job.Id)
    }

    #Remove all jobs created.
    $null = Get-Job | Remove-Job

    return $results

}


Function Get-JobBlock {

    $block = {
        Param([string] $Path, [bool] $Recurse = $true)

        #Make sure Path is found
        if (! (Test-Path -Path $Path) ) {
            return (New-Object PSObject -Property @{
                Folder = $Path
                Size = 0
                FilesCount = 0
                Error = "Path not found"
            })
        }

        #Enumate all child file items
        if ($Recurse) {
            $Children = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue -Attributes !o -File -Force -Recurse
        } else {
            $Children = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue -Attributes !o -File -Force
        }
                
        #Return an object with Folder, Size, FileCount and Error parameters
        return (New-Object PSObject -Property @{
            Folder = $Path
            Size = ($Children | Measure Length -Sum).Sum
            FilesCount = $Children.Count
            Error = $null
        })
        
    }
    return $block

}


#Helper function to print folders sizes in readable sizes
Function Format-Bytes {
    Param
    (
        [Parameter(
            ValueFromPipeline = $true
        )]
        [ValidateNotNullOrEmpty()]
        [float]$number
    )
    Begin{
        $sizes = 'KB','MB','GB','TB','PB'
    }
    Process {
        # New for loop
        for($x = 0;$x -lt $sizes.count; $x++){
            if ($number -lt "1$($sizes[$x])"){
                if ($x -eq 0){
                    return "$number B "
                } else {
                    $num = $number / "1$($sizes[$x-1])"
                    $num = "{0:N1}" -f $num
                    return "$num $($sizes[$x-1])"
                }
            }
        }
    }
    End{}
}


Main
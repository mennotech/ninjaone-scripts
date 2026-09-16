# --- NINJAONE MANAGED HEADER START ---
# ==============================================================================
# Script Name: Delete Windows User Profile
# ==============================================================================
#
# Description:
#   Returns the entire space used by all subfolders in the RootFolder specified
#
# Metadata:
#   - NinjaOne Script ID: 97
#   - Language: powershell
#   - OS Type: Windows
#   - Architecture: 64, 32
#   - Created By: Roland Penner
#   - Created On: 2025-05-31
#   - Last Updated By: Roland Penner
#   - Last Updated: 2025-06-18 22:06:14
#   - Active: True
# Script Variables (NinjaOne):
#   - userfolder (TEXT, Required): The name of the user's profile folder
#     Default: John
#
# ==============================================================================
# --- NINJAONE MANAGED HEADER END ---
<#
.SYNOPSIS
    This script removes a local copy of the user's profile directory and the corresponding registry entry.
.DESCRIPTION
    The script allows you to delete a local user profile by specifying the user's folder name.
    It searches for user profiles matching the specified folder name and removes them if found.
    If no matching profiles are found, it provides an error message.

    The script takes the following parameter:
      -UserFolder (REQUIRED)   The name of the user's folder to search for and delete.

.EXAMPLE
    -UserFolder "John"

Found matching profile: C:\users\johndoe. Deleting...
Done.

.OUTPUTS
    This script does not produce any output to the console unless there is an error or a profile is found and deleted.
    
.NOTES
    2025-06-18: Initial version of the script.
.LINK
    https://github.com/mennotech/rmm-scripts/blob/main/powershell/Delete-Windows-User-Profile.ps1

.LICENSE
    This script is released under the MIT License.

#>


Param(
    [string] $UserFolder = "Default"
)

# Replace parameters with dynamic script variables.
if ($env:UserFolder -and $env:UserFolder -notlike "null") { $UserFolder = $env:UserFolder }


$UserProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object { $_.LocalPath -match $UserFolder } 

if ($UserProfiles) {
  try {
      foreach ($Profile in $UserProfiles) {
	      Write-Host "Found matching profile: $($Profile.LocalPath). Deleting..."
          $Profile | Remove-WmiObject
	  }
  }
  catch {
      Write-Warning "An error occurred will attempting to delete profile"
      Exit 1
  }
} else {
  Write-Warning "No matching profiles found for $($UserFolder)"
  Exit 1
}

Write-Host "Done."
Exit 0
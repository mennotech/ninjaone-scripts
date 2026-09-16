REM --- NINJAONE MANAGED HEADER START ---
REM ==============================================================================
REM Script Name: Putty Registry Backup
REM ==============================================================================
REM
REM Description:
REM   A script to backup the putty configuration to a reg file store in the user's profile directory.
REM
REM Metadata:
REM   - NinjaOne Script ID: 98
REM   - Language: batchfile
REM   - OS Type: Windows
REM   - Architecture: 64, 32
REM   - Created By: Roland Penner
REM   - Created On: 2025-06-04
REM   - Last Updated By: Roland Penner
REM   - Last Updated: 2025-06-04 17:53:42
REM   - Active: True
REM ==============================================================================
REM --- NINJAONE MANAGED HEADER END ---
REM INSTRUCTIONS:
REM 1. Open NinjaOne GUI: https://ca.ninjarmm.com
REM 2. Navigate to: Administration → Library → Automation → Scripts
REM 3. Find and open: "Putty Registry Backup"
REM 4. Copy the entire script content
REM 5. Paste below this header (replace the placeholder comment)
REM 6. Save and commit to Git
REM ==============================================================================

@ECHO OFF

REM Default to exporting to Desktop folder
SET EXPORTPATH="%USERPROFILE%\Desktop\Putty-Backup.reg"

REM Override default if OneDrive environment variables are found
IF DEFINED OneDrive (SET EXPORTPATH="%OneDrive%\Putty-Backup.reg")
IF DEFINED OneDriveCommercial (SET EXPORTPATH="%OneDriveCommercial%\Putty-Backup.reg")

ECHO Saving Putty configuration to %EXPORTPATH%
REG EXPORT HKCU\Software\SimonTatham %EXPORTPATH% /y


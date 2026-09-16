REM --- NINJAONE MANAGED HEADER START ---
REM ==============================================================================
REM Script Name: Remove crowdstrike
REM ==============================================================================
REM
REM Description:
REM   No description provided
REM
REM Metadata:
REM   - NinjaOne Script ID: 83
REM   - Language: batchfile
REM   - OS Type: Windows
REM   - Architecture: 64
REM   - Created By: Roland Penner
REM   - Created On: 2025-04-17
REM   - Last Updated By: Roland Penner
REM   - Last Updated: 2025-04-17 14:08:06
REM   - Active: True
REM ==============================================================================
REM --- NINJAONE MANAGED HEADER END ---
REM INSTRUCTIONS:
REM 1. Open NinjaOne GUI: https://ca.ninjarmm.com
REM 2. Navigate to: Administration → Library → Automation → Scripts
REM 3. Find and open: "Remove crowdstrike"
REM 4. Copy the entire script content
REM 5. Paste below this header (replace the placeholder comment)
REM 6. Save and commit to Git
REM ==============================================================================
wmic product where name="CrowdStrike Device Control" call uninstall /nointeractive
wmic product where name="CrowdStrike Firmware Analysis" call uninstall /nointeractive
wmic product where name="CrowdStrike Sensor Platform" call uninstall /nointeractive
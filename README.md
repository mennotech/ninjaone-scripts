# ninja-one-scripts
Scripts Developed for managing systems with Ninja One

## Overview
This repository contains administrative scripts designed for NinjaOne RMM (Remote Monitoring and Management) platform. Scripts are primarily PowerShell-based and focus on Windows system management, monitoring, and automation.

## API Management Scripts

### Get-Scripts.ps1
Synchronizes NinjaOne script metadata with your local repository and helps keep scripts up-to-date.

> **Note**: The NinjaOne API does not expose script content - only metadata (names, descriptions, parameters, timestamps). This script helps track what scripts exist in NinjaOne and identifies which ones need to be manually copied from the GUI.

**Features:**
- Connects to NinjaOne API using OAuth2 authentication
- Retrieves metadata for all scripts from your NinjaOne instance
- Exports complete metadata to JSON for tracking and version control
- Creates stub files with comprehensive headers for new scripts
- Generates a sync report (SYNC-REPORT.md) identifying:
  - Scripts already in repository
  - New scripts that need manual copy from GUI
  - Last updated timestamps for change tracking
- Organizes scripts by OS Type and Language (e.g., Windows/PowerShell, Linux/Bash)
- Supports environment variables or .env file for credentials

**Prerequisites:**
- PowerShell 5.1 or higher
- NinjaOne API credentials with scopes: `monitoring management`
- Network access to your NinjaOne instance

**Setup:**
1. Create API credentials in NinjaOne (Administration > Apps > API)
   - Grant Type: `Client Credentials`
   - Required Scopes: `monitoring` and `management`
2. Copy `.env.example` to `.env` and fill in your credentials:
   ```
   NINJAONE_CLIENT_ID=your_client_id
   NINJAONE_CLIENT_SECRET=your_client_secret
   NINJAONE_INSTANCE=ca.ninjarmm.com
   NINJAONE_SCOPE=monitoring management
   ```
3. Alternatively, set environment variables instead of using .env file

**Usage:**
```powershell
# Check what scripts exist in NinjaOne and export metadata
.\bin\Get-Scripts.ps1

# Create stub files for new scripts with comprehensive headers
.\bin\Get-Scripts.ps1 -CreateStubs

# Include disabled scripts in the sync
.\bin\Get-Scripts.ps1 -CreateStubs -IncludeDisabled

# Use custom output path and .env file
.\bin\Get-Scripts.ps1 -OutputPath "C:\NinjaScripts" -EnvFilePath "C:\Secure\.env"
```

**Workflow:**
1. Run the script to generate SYNC-REPORT.md
2. Review the report to see new/updated scripts
3. For each script needing updates:
   - Open NinjaOne GUI (Administration → Library → Automation → Scripts)
   - Copy the script content
   - Paste into the local file (stub files created if using -CreateStubs)
4. Run `Update-ScriptHeaders.ps1` to add/update metadata headers
5. Test changes locally if possible
6. Commit to Git with meaningful messages
7. Re-run periodically to check for changes

**Files Generated:**
- `scripts-metadata.json`: Complete metadata export for all scripts
- `SYNC-REPORT.md`: Actionable report with manual copy instructions
- Stub files: Pre-created files with metadata headers (when using -CreateStubs)
- Files are named with format: `[ID]-[Script Name].[ext]` (e.g., `104-Block Windows Shell Extensions.ps1`)

### Update-ScriptHeaders.ps1
Automatically creates missing stubs and updates metadata headers for scripts that have actual content.

**Features:**
- Auto-discovers all script files in repository
- Creates stub files for metadata entries without a corresponding local script
- Matches files by Script ID (extracted from filename prefix)
- Detects metadata changes by comparing timestamps
- Renames files to match current script name in NinjaOne (preserves ID prefix)
- Updates headers only when metadata has changed
- Skips stub files (files with "TODO: Paste script content")
- Supports all script languages (PowerShell, Batch, Shell, Python, etc.)

**Prerequisites:**
- `scripts-metadata.json` must exist (run `Get-Scripts.ps1` first)
- Files must be in `ID-Name` format (automatically handled by Get-Scripts.ps1)

**Usage:**
```powershell
# Update headers for all scripts with content
.\bin\Update-ScriptHeaders.ps1

# Run with verbose output to see what's being processed
.\bin\Update-ScriptHeaders.ps1 -Verbose
```

**When to Run:**
- After pasting script content from NinjaOne GUI into stub files
- After running `Get-Scripts.ps1` to refresh metadata
- When script names change in NinjaOne (automatically renames local files)
- Periodically to ensure headers stay in sync with NinjaOne metadata

**What it Updates:**
- Script name, description, and NinjaOne Script ID
- Last updated timestamps and author information
- Script variables and parameters documentation
- OS type, architecture, and language information

**File Naming:**
Scripts are automatically named using the format: `[ID]-[Script Name].[extension]`
- Example: `104-Block Windows Shell Extensions.ps1`
- The ID prefix ensures unique identification even if scripts are renamed
- Allows the update script to track renames and update files accordingly

## Complete Workflow

### Initial Setup
1. Create NinjaOne API credentials (Administration > Apps > API)
2. Copy `.env.example` to `.env` and configure credentials
3. Run `.\bin\Get-Scripts.ps1 -CreateStubs` to initialize repository

### Regular Sync Process
```powershell
# Step 1: Sync metadata and create stub files for new scripts
.\bin\Get-Scripts.ps1 -CreateStubs

# Step 2: Review SYNC-REPORT.md for new/updated scripts

# Step 3: For each new script (copy content from NinjaOne GUI):
#   - Open NinjaOne → Administration → Library → Automation → Scripts
#   - Find the script by name
#   - Copy the entire script content
#   - Paste into the corresponding stub file (replacing the TODO comment)

# Step 4: Update headers for newly populated scripts
.\bin\Update-ScriptHeaders.ps1

# Step 5: Review changes and commit to Git
git add .
git commit -m "Added/updated scripts from NinjaOne"
git push
```

### When Scripts are Renamed in NinjaOne
```powershell
# Step 1: Refresh metadata
.\bin\Get-Scripts.ps1

# Step 2: Update headers (automatically detects and renames files)
.\bin\Update-ScriptHeaders.ps1

# The script will:
# - Detect the rename via Script ID
# - Rename the local file to match
# - Update the header with new metadata
# - Preserve all script content
```

### Periodic Maintenance
Run these commands weekly or after making changes in NinjaOne:
```powershell
.\bin\Get-Scripts.ps1            # Refresh metadata
.\bin\Update-ScriptHeaders.ps1   # Create missing stubs and update changed headers
```

## Folder Structure
```
ninja-one-scripts/
├── bin
│   ├── Get-Scripts.ps1           # API metadata sync script
│   └── Update-ScriptHeaders.ps1  # Header update and file rename script
├── .env.example                  # Configuration template
├── db
│   └── scripts-metadata.json     # Metadata export from NinjaOne
├── SYNC-REPORT.md                # Sync status report
├── Windows/
│   ├── PowerShell/               # Windows PowerShell scripts
│   │   ├── 104-Block Windows Shell Extensions.ps1
│   │   ├── 105-Get OneDrive Sync Status.ps1
│   │   └── ...
│   └── Batchfile/                # Batch scripts
│       ├── 83-Remove crowdstrike.bat
│       └── ...
├── Linux/
│   └── Sh/                       # Linux shell scripts
│       └── 101-Find Large Folders.sh
└── macOS/                        # macOS scripts (future)
```

**File Naming Convention:**
All script files use the format: `[NinjaOne Script ID]-[Script Name].[extension]`
- The ID prefix ensures unique identification
- Scripts can be renamed in NinjaOne without losing local changes
- `Update-ScriptHeaders.ps1` automatically handles renames

## Contributing
When adding new scripts, please follow the PowerShell standards outlined in `.github/copilot-instructions.md`.

## License
MIT License - See LICENSE file for details

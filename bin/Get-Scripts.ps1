<#
.SYNOPSIS
    Syncs NinjaOne script metadata with local repository and creates stub files for manual script content management.

.DESCRIPTION
    This script connects to the NinjaOne API using OAuth2 authentication to retrieve all configured scripts metadata.
    
    IMPORTANT: The NinjaOne Public API does not provide access to actual script content/code.
    
    This script helps maintain synchronization between NinjaOne and your local repository by:
    1. Fetching script metadata (names, descriptions, parameters, OS types, languages, timestamps)
    2. Comparing with existing local files to identify new/updated/orphaned scripts
    3. Creating stub files with proper headers for scripts that need manual updates
    4. Generating a sync report showing what needs to be copy-pasted from NinjaOne GUI
    5. Exporting metadata to JSON for tracking and comparison
    
    Workflow:
    1. Run this script to sync metadata and identify changes
    2. Review the generated sync report
    3. For new/updated scripts, manually copy code from NinjaOne GUI and paste into stub files
    4. Commit changes to Git with metadata tracking
    
    Authentication credentials can be provided via environment variables (priority) or a .env file.
    
    Required credentials:
    - NINJAONE_CLIENT_ID: OAuth2 Client ID
    - NINJAONE_CLIENT_SECRET: OAuth2 Client Secret
    - NINJAONE_INSTANCE: Instance URL (e.g., app.ninjarmm.com or eu.ninjarmm.com)
    - NINJAONE_SCOPE: OAuth2 scope (use 'monitoring management' for best results)

.PARAMETER OutputPath
    The base directory where scripts will be saved. Defaults to the current directory.

.PARAMETER EnvFilePath
    Path to the .env file containing API credentials. Defaults to '.env' in the repository root.

.PARAMETER IncludeDisabled
    Include disabled scripts in the sync. By default, only active/enabled scripts are synced.

.PARAMETER CreateStubs
    Create stub files for new scripts with metadata headers. Makes it easy to copy-paste code from NinjaOne GUI.

.PARAMETER ForceEnvFile
    Force credentials from .env file to override existing environment variables. 
    By default, environment variables take priority over .env file values.
    Use this switch when you've updated credentials in .env and want to override stale environment variables.

.OUTPUTS
    System.String
    Outputs status messages and saves scripts to disk in OSType\Language folder structure.

.NOTES
    Version: 1.1.0
    Author: NinjaOne Scripts Project
    Created: 2026-02-20
    
    Version History:
    1.1.0 - 2026-09-15 - Changed the default .env path to the repository root and return an explicit success exit code.
    1.0.0 - 2026-02-20 - Initial release

.LINK
    https://github.com/mennotech/ninja-one-scripts

.LICENSE
    MIT License - See LICENSE file in repository root

.EXAMPLE
    .\Get-Scripts.ps1
    Syncs metadata for all enabled scripts and generates a report.

.EXAMPLE
    .\Get-Scripts.ps1 -CreateStubs
    Syncs metadata and creates stub files for new/updated scripts that need manual code updates.

.EXAMPLE
    .\Get-Scripts.ps1 -OutputPath "C:\NinjaScripts" -IncludeDisabled -CreateStubs
    Syncs all scripts (including disabled) and creates stub files in C:\NinjaScripts.

.EXAMPLE
    .\Get-Scripts.ps1 -EnvFilePath "C:\Secure\.env"
    Syncs using credentials from a custom .env file location.

.EXAMPLE
    .\Get-Scripts.ps1 -ForceEnvFile
    Forces credentials from .env file to override any existing environment variables.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [String]$OutputPath = (Get-Location).Path,
    
    [Parameter()]
    [String]$EnvFilePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath ".env"),
    
    [Parameter()]
    [Switch]$IncludeDisabled,
    
    [Parameter()]
    [Switch]$CreateStubs,
    
    [Parameter()]
    [Switch]$ForceEnvFile
)

begin {
    Write-Host "NinjaOne Script Downloader" -ForegroundColor Cyan
    Write-Host "==========================`n" -ForegroundColor Cyan
    
    #region Functions
    
    function Import-EnvFile {
        <#
        .SYNOPSIS
            Imports environment variables from a .env file.
        #>
        param(
            [Parameter(Mandatory = $true)]
            [String]$Path,
            
            [Parameter()]
            [Switch]$Force
        )
        
        if (-not (Test-Path -Path $Path)) {
            Write-Verbose "No .env file found at: $Path"
            return $false
        }
        
        Write-Verbose "Loading .env file from: $Path"
        
        try {
            Get-Content -Path $Path -ErrorAction Stop | ForEach-Object {
                $line = $_.Trim()
                
                # Skip empty lines and comments
                if ($line -and $line -notmatch '^\s*#') {
                    if ($line -match '^([^=]+)=(.*)$') {
                        $key = $matches[1].Trim()
                        $value = $matches[2].Trim()
                        
                        # Remove quotes if present
                        $value = $value -replace '^["'']|["'']$', ''
                        
                        # Set environment variable (respecting Force parameter)
                        $alreadyExists = $null -ne (Get-Item -Path "Env:$key" -ErrorAction SilentlyContinue)
                        if ($Force -or -not $alreadyExists) {
                            Set-Item -Path "Env:$key" -Value $value
                            if ($Force -and $alreadyExists) {
                                Write-Verbose "Overrode existing environment variable: $key"
                            } else {
                                Write-Verbose "Loaded from .env: $key"
                            }
                        }
                    }
                }
            }
            return $true
        }
        catch {
            Write-Warning "Failed to load .env file: $_"
            return $false
        }
    }
    
    function Get-NinjaOneAccessToken {
        <#
        .SYNOPSIS
            Obtains an OAuth2 access token from NinjaOne API using Client Credentials Flow.
        .DESCRIPTION
            Implements the Client Credentials Flow as documented at:
            https://app.ninjarmm.com/apidocs-beta/authorization/flows/client-credentials-flow
        #>
        param(
            [Parameter(Mandatory = $true)]
            [String]$ClientId,
            
            [Parameter(Mandatory = $true)]
            [String]$ClientSecret,
            
            [Parameter(Mandatory = $true)]
            [String]$Instance,
            
            [Parameter()]
            [String]$Scope = ""
        )
        
        # OAuth2 Token Endpoint as per NinjaOne API documentation
        $tokenUrl = "https://$Instance/ws/oauth/token"
        
        # Build request body per Client Credentials Flow specification
        $body = @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
        }
        
        # Add scope parameter (optional, defaults to all configured scopes in the API application)
        if ($Scope -and $Scope -ne "") {
            $body.scope = $Scope
        }
        
        try {
            Write-Verbose "Requesting access token from: $tokenUrl"
            Write-Verbose "Client ID: $($ClientId.Substring(0, [Math]::Min(10, $ClientId.Length)))..."
            if ($Scope) {
                Write-Verbose "Requested scope: $Scope"
            } else {
                Write-Verbose "Using default scopes configured in API application"
            }
            
            # POST request with form-urlencoded body as per OAuth2 specification
            $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
            
            Write-Verbose "Successfully obtained access token"
            Write-Verbose "Token type: $($response.token_type)"
            Write-Verbose "Expires in: $($response.expires_in) seconds"
            Write-Verbose "Granted scope: $($response.scope)"
            
            return $response.access_token
        }
        catch {
            $errorMessage = $_.Exception.Message
            $errorDetails = ""
            
            if ($_.ErrorDetails.Message) {
                try {
                    $errorObj = $_.ErrorDetails.Message | ConvertFrom-Json
                    $errorDetails = $_.ErrorDetails.Message
                    
                    # Provide specific guidance based on error type
                    if ($errorObj.error -eq "invalid_client" -or $errorObj.resultCode -eq "Client app not exist") {
                        Write-Host "`nAuthentication Error: Invalid Client Credentials" -ForegroundColor Red
                        Write-Host "The Client ID or Client Secret is incorrect, or the API application doesn't exist.`n" -ForegroundColor Yellow
                        Write-Host "Please verify:" -ForegroundColor Yellow
                        Write-Host "  1. Go to Administration > Apps > API in NinjaOne" -ForegroundColor Gray
                        Write-Host "  2. Confirm your API application exists and matches:" -ForegroundColor Gray
                        Write-Host "     Client ID: $($ClientId.Substring(0, [Math]::Min(15, $ClientId.Length)))..." -ForegroundColor Gray
                        Write-Host "  3. Copy the Client ID and Client Secret again (check for extra spaces)" -ForegroundColor Gray
                        Write-Host "  4. Update your .env file with the correct values" -ForegroundColor Gray
                    }
                    elseif ($errorObj.error -eq "unauthorized_client") {
                        Write-Host "`nAuthentication Error: Unauthorized Client" -ForegroundColor Red
                        Write-Host "The API application is not authorized for Client Credentials grant type.`n" -ForegroundColor Yellow
                        Write-Host "Please verify:" -ForegroundColor Yellow
                        Write-Host "  1. Go to Administration > Apps > API in NinjaOne" -ForegroundColor Gray
                        Write-Host "  2. Edit your API application" -ForegroundColor Gray
                        Write-Host "  3. Ensure 'Client Credentials' is checked under 'Allowed Grant Types'" -ForegroundColor Gray
                        Write-Host "  4. Regenerate credentials after making changes" -ForegroundColor Gray
                    }
                    elseif ($errorObj.error -eq "invalid_scope") {
                        Write-Host "`nAuthentication Error: Invalid Scope" -ForegroundColor Red
                        Write-Host "The requested scope '$Scope' is not configured for this API application.`n" -ForegroundColor Yellow
                        Write-Host "Please verify:" -ForegroundColor Yellow
                        Write-Host "  1. Go to Administration > Apps > API in NinjaOne" -ForegroundColor Gray
                        Write-Host "  2. Edit your API application" -ForegroundColor Gray
                        Write-Host "  3. Check the 'Scopes' section (Monitoring, Management, Control)" -ForegroundColor Gray
                        Write-Host "  4. Ensure the required scopes are enabled" -ForegroundColor Gray
                        Write-Host "  5. Try removing NINJAONE_SCOPE from .env to use default scopes" -ForegroundColor Gray
                    }
                    else {
                        Write-Host "`nAuthentication Error: $($errorObj.error)" -ForegroundColor Red
                        Write-Host "$errorDetails`n" -ForegroundColor Yellow
                    }
                }
                catch {
                    Write-Host "`nError: $errorMessage" -ForegroundColor Red
                    Write-Host "$($_.ErrorDetails.Message)`n" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "`nError: $errorMessage`n" -ForegroundColor Red
            }
            
            Write-Error "Failed to obtain access token. See messages above for details."
            throw
        }
    }
    
    function Get-NinjaOneScripts {
        <#
        .SYNOPSIS
            Retrieves all scripts from NinjaOne API.
        #>
        param(
            [Parameter(Mandatory = $true)]
            [String]$AccessToken,
            
            [Parameter(Mandatory = $true)]
            [String]$Instance
        )
        
        $apiUrl = "https://$Instance/api/v2/automation/scripts"
        
        $headers = @{
            Authorization = "Bearer $AccessToken"
            Accept        = "application/json"
        }
        
        try {
            Write-Verbose "Retrieving scripts from: $apiUrl"
            
            $scripts = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -ErrorAction Stop
            
            Write-Verbose "Successfully retrieved $($scripts.Count) script(s)"
            return $scripts
        }
        catch {
            Write-Error "Failed to retrieve scripts: $_"
            throw
        }
    }
    
    function Get-NinjaOneScript {
        <#
        .SYNOPSIS
            Retrieves a specific script's details from NinjaOne API.
        #>
        param(
            [Parameter(Mandatory = $true)]
            [String]$AccessToken,
            
            [Parameter(Mandatory = $true)]
            [String]$Instance,
            
            [Parameter(Mandatory = $true)]
            [String]$ScriptId
        )
        
        $apiUrl = "https://$Instance/api/v2/automation/scripts/$ScriptId"
        
        $headers = @{
            Authorization = "Bearer $AccessToken"
            Accept        = "application/json"
        }
        
        try {
            Write-Verbose "Retrieving script details for ID: $ScriptId"
            
            $script = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -ErrorAction Stop
            
            return $script
        }
        catch {
            # Don't use Write-Error here - let the caller handle error output
            throw
        }
    }
    
    function Get-ScriptFileExtension {
        <#
        .SYNOPSIS
            Determines the file extension based on script language.
        #>
        param(
            [Parameter(Mandatory = $true)]
            [String]$Language
        )
        
        switch ($Language.ToLower()) {
            'powershell' { return '.ps1' }
            { $_ -in 'batch', 'batchfile' } { return '.bat' }
            { $_ -in 'bash', 'sh' } { return '.sh' }
            'python' { return '.py' }
            'javascript' { return '.js' }
            'vbscript' { return '.vbs' }
            default { return '.txt' }
        }
    }
    
    function Get-OSTypeFolder {
        <#
        .SYNOPSIS
            Maps NinjaOne OS types to folder names.
        #>
        param(
            [Parameter(Mandatory = $true)]
            [String]$OSType
        )
        
        switch ($OSType.ToLower()) {
            'windows' { return 'Windows' }
            'mac' { return 'macOS' }
            'macos' { return 'macOS' }
            'linux' { return 'Linux' }
            default { return 'Unknown' }
        }
    }
    
    function Save-NinjaScriptStub {
        <#
        .SYNOPSIS
            Creates a stub file with metadata headers for manual script content entry.
        .DESCRIPTION
            Since NinjaOne API doesn't provide script content, this creates a properly structured
            file with metadata that makes it easy to copy-paste code from the NinjaOne GUI.
        #>
        param(
            [Parameter(Mandatory = $true)]
            [PSCustomObject]$Script,
            
            [Parameter(Mandatory = $true)]
            [String]$BasePath
        )
        
        # Determine OS type folder (use first OS if multiple)
        $osType = if ($Script.operatingSystems -and $Script.operatingSystems.Count -gt 0) {
            $Script.operatingSystems[0]
        } else {
            "Unknown"
        }
        $osFolder = Get-OSTypeFolder -OSType $osType
        
        # Determine language folder (capitalize first letter)
        $language = $Script.language
        if ($language) {
            $languageFolder = $language.Substring(0, 1).ToUpper() + $language.Substring(1).ToLower()
        }
        else {
            $languageFolder = "Unknown"
        }
        
        # Create folder path
        $folderPath = Join-Path -Path $BasePath -ChildPath "$osFolder\$languageFolder"
        
        if (-not (Test-Path -Path $folderPath)) {
            New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
            Write-Verbose "Created directory: $folderPath"
        }
        
        # Determine file extension
        $extension = Get-ScriptFileExtension -Language $Script.language
        
        # Sanitize filename and prefix with Script ID
        $scriptName = $Script.name -replace '[<>:"/\\|?*]', '_'
        $fileName = "$($Script.id)-$scriptName$extension"
        
        $filePath = Join-Path -Path $folderPath -ChildPath $fileName
        
        # Build metadata header based on language
        $commentChar = switch ($Script.language.ToLower()) {
            'powershell' { '#' }
            { $_ -in 'batch', 'batchfile' } { 'REM' }
            { $_ -in 'bash', 'sh' } { '#' }
            'python' { '#' }
            'javascript' { '//' }
            'vbscript' { "'" }
            default { '#' }
        }
        
        # Create comprehensive metadata header
        $updateDate = [DateTimeOffset]::FromUnixTimeSeconds($Script.updatedOn).DateTime.ToString("yyyy-MM-dd HH:mm:ss")
        $createDate = [DateTimeOffset]::FromUnixTimeSeconds($Script.createdOn).DateTime.ToString("yyyy-MM-dd")
        
        # Format description with proper comment markers for multi-line content
        $formattedDescription = if ($Script.description) {
            # Handle both literal \n and actual newlines
            $desc = $Script.description -replace '\\n', "`n"
            # Split by newlines, trim each line, filter empty lines, and join with proper comment prefix
            ($desc -split '[\r\n]+' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }) -join "`n$commentChar   "
        } else {
            "No description provided"
        }
        
        $header = @"
$commentChar --- NINJAONE MANAGED HEADER START ---
$commentChar ==============================================================================
$commentChar Script Name: $($Script.name)
$commentChar ==============================================================================
$commentChar
$commentChar Description:
$commentChar   $formattedDescription
$commentChar
$commentChar Metadata:
$commentChar   - NinjaOne Script ID: $($Script.id)
$commentChar   - Language: $($Script.language)
$commentChar   - OS Type: $($osType)
$commentChar   - Architecture: $($Script.architecture -join ', ')
$commentChar   - Created By: $(if ($Script.createdBy) { $Script.createdBy } else { 'N/A' })
$commentChar   - Created On: $createDate
$commentChar   - Last Updated By: $(if ($Script.lastUpdatedBy) { $Script.lastUpdatedBy } else { 'N/A' })
$commentChar   - Last Updated: $updateDate
$commentChar   - Active: $($Script.active)

"@
        
        # Add script parameters information if present
        if ($Script.scriptParameters -and $Script.scriptParameters.Count -gt 0) {
            $header += "$commentChar Script Parameters:`n"
            foreach ($param in $Script.scriptParameters) {
                # Format parameter description with proper handling of newlines
                $paramDesc = if ($param.description) {
                    $desc = $param.description -replace '\\n', "`n"
                    ($desc -split '[\r\n]+' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }) -join " "
                } else { "" }
                $header += "$commentChar   - $($param.name): $paramDesc`n"
            }
            $header += "$commentChar`n"
        }
        
        # Add script variables information if present
        if ($Script.scriptVariables -and $Script.scriptVariables.Count -gt 0) {
            $header += "$commentChar Script Variables (NinjaOne):`n"
            foreach ($var in $Script.scriptVariables) {
                $required = if ($var.required) { "Required" } else { "Optional" }
                # Format variable description with proper handling of newlines
                $varDesc = if ($var.description) {
                    $desc = $var.description -replace '\\n', "`n"
                    ($desc -split '[\r\n]+' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }) -join " "
                } else { "" }
                $header += "$commentChar   - $($var.id) ($($var.type), $required): $varDesc`n"
                if ($var.defaultValue) {
                    $header += "$commentChar     Default: $($var.defaultValue)`n"
                }
            }
            $header += "$commentChar`n"
        }
        
        $header += @"
$commentChar ==============================================================================
$commentChar --- NINJAONE MANAGED HEADER END ---
    $commentChar
$commentChar INSTRUCTIONS FOR STUB FILES:
$commentChar 1. Open NinjaOne GUI: https://$instance
$commentChar 2. Navigate to: Administration → Library → Automation → Scripts
$commentChar 3. Find and open: "$($Script.name)"
$commentChar 4. Copy the entire script content
$commentChar 5. REPLACE EVERYTHING BELOW (from INSTRUCTIONS to TODO) with the actual code
$commentChar 6. Save and commit to Git
$commentChar
$commentChar TODO: Paste script content from NinjaOne GUI here
"@
        
        # Check if file already exists with actual content (not a stub)
        if (Test-Path $filePath) {
            $existingContent = Get-Content $filePath -Raw -ErrorAction SilentlyContinue
            if ($existingContent -and $existingContent -notmatch 'TODO: Paste script content from NinjaOne GUI') {
                Write-Host "  [SKIP] File exists with content: $osFolder\$languageFolder\$fileName" -ForegroundColor Yellow
                return $filePath
            }
        }
        
        # Save stub file
        try {
            Set-Content -Path $filePath -Value $header -Encoding UTF8 -ErrorAction Stop
            
            Write-Host "  [+] Created stub: $osFolder\$languageFolder\$fileName" -ForegroundColor Green
            
            return $filePath
        }
        catch {
            Write-Warning "Failed to create stub for '$($Script.name)': $_"
            return $null
        }
    }
    
    #endregion
    
    #region Main Script Execution
    
    # Load .env file if environment variables are not set OR if ForceEnvFile is specified
    if ($ForceEnvFile) {
        Write-Host "ForceEnvFile specified. Loading credentials from .env file..." -ForegroundColor Yellow
        Import-EnvFile -Path $EnvFilePath -Force | Out-Null
    }
    elseif (-not $env:NINJAONE_CLIENT_ID -or -not $env:NINJAONE_CLIENT_SECRET -or -not $env:NINJAONE_INSTANCE) {
        Write-Host "Environment variables not found. Attempting to load from .env file..." -ForegroundColor Yellow
        Import-EnvFile -Path $EnvFilePath | Out-Null
    }
    else {
        Write-Verbose "Using existing environment variables (use -ForceEnvFile to override with .env file)"
    }
    
    # Validate required credentials
    $clientId = $env:NINJAONE_CLIENT_ID
    $clientSecret = $env:NINJAONE_CLIENT_SECRET
    $instance = $env:NINJAONE_INSTANCE
    $scope = $env:NINJAONE_SCOPE
    
    if (-not $clientId -or -not $clientSecret -or -not $instance) {
        Write-Error "Missing required credentials. Please set the following environment variables or add them to a .env file:"
        Write-Error "  - NINJAONE_CLIENT_ID"
        Write-Error "  - NINJAONE_CLIENT_SECRET"
        Write-Error "  - NINJAONE_INSTANCE (e.g., app.ninjarmm.com)"
        Write-Error "  - NINJAONE_SCOPE (optional, defaults to 'monitoring')"
        exit 1
    }
    
    # Validate instance is a safe hostname to prevent unintended URL construction
    if ($instance -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$') {
        Write-Error "Invalid NINJAONE_INSTANCE value '$instance'. Expected a hostname like 'app.ninjarmm.com'."
        exit 1
    }
    
    Write-Host "Configuration:" -ForegroundColor Cyan
    Write-Host "  Instance: $instance" -ForegroundColor Gray
    Write-Host "  Output Path: $OutputPath" -ForegroundColor Gray
    Write-Host "  Include Disabled: $IncludeDisabled" -ForegroundColor Gray
    Write-Host ""
    
    # Validate output path
    if (-not (Test-Path -Path $OutputPath)) {
        try {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
            Write-Verbose "Created output directory: $OutputPath"
        }
        catch {
            Write-Error "Failed to create output directory: $_"
            exit 1
        }
    }
}

process {
    try {
        # Get access token
        Write-Host "Authenticating to NinjaOne API..." -ForegroundColor Cyan
        
        $accessToken = Get-NinjaOneAccessToken -ClientId $clientId -ClientSecret $clientSecret -Instance $instance -Scope $scope
        
        Write-Host "Successfully authenticated!`n" -ForegroundColor Green
        
        # Get all scripts metadata
        Write-Host "Retrieving scripts metadata from NinjaOne..." -ForegroundColor Cyan
        
        $scripts = Get-NinjaOneScripts -AccessToken $accessToken -Instance $instance
        
        if (-not $scripts -or $scripts.Count -eq 0) {
            Write-Warning "No scripts found in NinjaOne."
            exit 0
        }
        
        Write-Host "Found $($scripts.Count) script(s)`n" -ForegroundColor Green
        
        # Filter built-in/native scripts (these are NinjaOne built-in actions, not custom scripts)
        $nativeScripts = $scripts | Where-Object { $_.language -eq 'native' -or $_.language -eq 'builtin' }
        $customScripts = $scripts | Where-Object { $_.language -ne 'native' -and $_.language -ne 'builtin' }
        
        if ($nativeScripts.Count -gt 0) {
            Write-Verbose "Excluding $($nativeScripts.Count) built-in/native action(s)"
        }
        
        # Filter disabled scripts if necessary
        if (-not $IncludeDisabled) {
            $scriptsToSync = $customScripts | Where-Object { $_.active -eq $true }
            $disabledCount = $customScripts.Count - $scriptsToSync.Count
            
            if ($disabledCount -gt 0) {
                Write-Host "Excluding $disabledCount disabled script(s)`n" -ForegroundColor Yellow
            }
        }
        else {
            $scriptsToSync = $customScripts
        }
        
        if ($scriptsToSync.Count -eq 0) {
            Write-Warning "No scripts to sync."
            exit 0
        }
        
        Write-Host "Syncing $($scriptsToSync.Count) script(s)...`n" -ForegroundColor Cyan
        
        # Export metadata to JSON
        $metadataDir = Join-Path -Path $OutputPath -ChildPath "db"
        
        # Ensure metadata directory exists
        if (-not (Test-Path -Path $metadataDir)) {
            New-Item -Path $metadataDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Created metadata directory: $metadataDir"
        }

        $metadataPath = Join-Path -Path $metadataDir -ChildPath "scripts-metadata.json"

        $scriptsToSync | ConvertTo-Json -Depth 10 | Set-Content -Path $metadataPath -Encoding UTF8
        Write-Host "[✓] Exported metadata to: $metadataPath" -ForegroundColor Green
        
        # Analyze scripts and create stub files if requested
        $newScripts = @()
        $updatedScripts = @()
        $upToDateScripts = @()
        $stubsCreated = 0
        
        foreach ($script in $scriptsToSync) {
            $osFolder = Get-OSTypeFolder -OSType $script.operatingSystems[0]
            $language = $script.language
            if ($language) {
                $languageFolder = $language.Substring(0, 1).ToUpper() + $language.Substring(1).ToLower()
            }
            else {
                $languageFolder = "Unknown"
            }
            
            $extension = Get-ScriptFileExtension -Language $script.language
            $scriptName = $script.name -replace '[<>:"/\\|?*]', '_'
            $fileName = "$($script.id)-$scriptName$extension"
            $filePath = Join-Path -Path $OutputPath -ChildPath "$osFolder\$languageFolder\$fileName"
            
            $metadataTimestamp = [DateTimeOffset]::FromUnixTimeSeconds($script.updatedOn).DateTime.ToString("yyyy-MM-dd HH:mm:ss")
            
            if (Test-Path -Path $filePath) {
                # File exists - check if it's a stub or has content
                $fileContent = Get-Content -Path $filePath -Raw -ErrorAction SilentlyContinue
                
                if ($fileContent -match 'TODO: Paste script content from NinjaOne GUI') {
                    # It's a stub file - treat as new
                    $newScripts += [PSCustomObject]@{
                        Name = $script.name
                        Path = "$osFolder\$languageFolder\$fileName"
                        ID   = $script.id
                        Description = $script.description
                        LastUpdated = $metadataTimestamp
                    }
                }
                else {
                    # Has content - check if metadata has changed
                    $fileTimestamp = $null
                    if ($fileContent -match 'Last Updated:\s*([^\r\n]+)') {
                        $fileTimestamp = $matches[1].Trim()
                    }
                    
                    if ($fileTimestamp -and $fileTimestamp -ne $metadataTimestamp) {
                        # Metadata has changed in NinjaOne
                        $updatedScripts += [PSCustomObject]@{
                            Name = $script.name
                            Path = "$osFolder\$languageFolder\$fileName"
                            ID   = $script.id
                            Description = $script.description
                            FileTimestamp = $fileTimestamp
                            NinjaOneTimestamp = $metadataTimestamp
                        }
                    }
                    else {
                        # Up to date
                        $upToDateScripts += [PSCustomObject]@{
                            Name = $script.name
                            Path = "$osFolder\$languageFolder\$fileName"
                            ID   = $script.id
                            LastUpdated = $metadataTimestamp
                        }
                    }
                }
            }
            else {
                $newScripts += [PSCustomObject]@{
                    Name = $script.name
                    Path = "$osFolder\$languageFolder\$fileName"
                    ID   = $script.id
                    Description = $script.description
                    LastUpdated = $metadataTimestamp
                }
                
                if ($CreateStubs) {
                    $stubPath = Save-NinjaScriptStub -Script $script -BasePath $OutputPath
                    if ($stubPath) {
                        $stubsCreated++
                    }
                }
            }
        }
        
        # Generate sync report
        Write-Host "`nSync Analysis:" -ForegroundColor Cyan
        Write-Host "==============" -ForegroundColor Cyan
        Write-Host "  Total scripts in NinjaOne: $($scriptsToSync.Count)" -ForegroundColor Gray
        Write-Host "  Up to date: $($upToDateScripts.Count)" -ForegroundColor Green
        Write-Host "  Updated in NinjaOne (review needed): $($updatedScripts.Count)" -ForegroundColor Yellow
        Write-Host "  New scripts (need manual copy): $($newScripts.Count)" -ForegroundColor Yellow
        
        if ($CreateStubs) {
            Write-Host "  Stub files created: $stubsCreated" -ForegroundColor Cyan
        }
        
        # Create detailed sync report
        if ($newScripts.Count -gt 0 -or $updatedScripts.Count -gt 0 -or $upToDateScripts.Count -gt 0) {
            $reportPath = Join-Path -Path $OutputPath -ChildPath "SYNC-REPORT.md"
            $reportContent = @"
# NinjaOne Scripts Sync Report
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Summary
- **Total Scripts in NinjaOne:** $($scriptsToSync.Count)
- **Up to Date:** $($upToDateScripts.Count)
- **Updated in NinjaOne (Review Needed):** $($updatedScripts.Count)
- **New Scripts (Need Manual Copy):** $($newScripts.Count)

## Action Required
$(if ($updatedScripts.Count -gt 0) {
@"

### UPDATED SCRIPTS - Metadata Changed in NinjaOne
These scripts exist locally with content but have been updated in NinjaOne. Review and update if needed.

$(
    $updatedScripts | ForEach-Object {
        @"
#### [$($_.Name)]
- **File:** ``$($_.Path)``
- **NinjaOne Script ID:** $($_.ID)
- **Description:** $($_.Description)
- **Local File Timestamp:** $($_.FileTimestamp)
- **NinjaOne Timestamp:** $($_.NinjaOneTimestamp)
- **Action:** 
  1. Run ``Update-ScriptHeaders.ps1`` to update metadata headers
  2. Check if script content was also changed in NinjaOne GUI
  3. If content changed, copy from NinjaOne and paste into ``$($_.Path)``
  4. Test and commit to Git

"@
    }
)
"@
} else {
    ""
})
$(if ($newScripts.Count -gt 0) {
@"

### NEW SCRIPTS - Need Manual Copy-Paste from NinjaOne GUI
$(
    $newScripts | ForEach-Object {
        @"

#### [$($_.Name)]
- **File:** ``$($_.Path)``
- **NinjaOne Script ID:** $($_.ID)
- **Description:** $($_.Description)
- **Last Updated:** $($_.LastUpdated)
- **Action:** 
  1. Open NinjaOne GUI → Administration → Scripts → Find '$($_.Name)'
  2. Copy the script content
$(if ($CreateStubs) { "  3. Paste into the stub file: ``$($_.Path)``
  4. Remove the placeholder comment" } else { "  3. Create file: ``$($_.Path)``
  4. Paste the content" })
  5. Review and test
  6. Commit to Git

"@
    }
)
"@
} else {
    ""
})
$(if ($upToDateScripts.Count -gt 0) {
@"

### UP TO DATE SCRIPTS
These scripts are synced with NinjaOne and don't need updates.

$(
    $upToDateScripts | ForEach-Object {
        "- **$($_.Name)** (``$($_.Path)``) - Last updated: $($_.LastUpdated)`n"
    }
)
"@
} else {
    ""
})

## Workflow
1. Review this report to see what needs manual updates
2. For updated scripts, run ``Update-ScriptHeaders.ps1`` to update metadata
3. For new scripts, copy content from NinjaOne GUI
4. Paste into the appropriate file (stub files are pre-created if -CreateStubs was used)
5. Test locally if possible
6. Commit changes to Git with meaningful commit messages
7. Re-run this script periodically to check for updates

## NinjaOne GUI Access
- **URL:** https://$instance
- **Path:** Administration → Library → Automation → Scripts

---
*This report was generated by Get-Scripts.ps1*
*Metadata exported to: scripts-metadata.json*
"@
            Set-Content -Path $reportPath -Value $reportContent -Encoding UTF8
            Write-Host "`n[✓] Generated sync report: SYNC-REPORT.md" -ForegroundColor Green
        }
        
        Write-Host "`n" -NoNewline
        if ($newScripts.Count -gt 0 -or $updatedScripts.Count -gt 0) {
            Write-Host "⚠ Action Required: " -ForegroundColor Yellow -NoNewline
            $actionItems = @()
            if ($newScripts.Count -gt 0) {
                $actionItems += "$($newScripts.Count) new script(s) need to be copied from NinjaOne GUI"
            }
            if ($updatedScripts.Count -gt 0) {
                $actionItems += "$($updatedScripts.Count) script(s) updated in NinjaOne"
            }
            Write-Host ($actionItems -join ", ")
            Write-Host "   Review SYNC-REPORT.md for details." -ForegroundColor Gray
        }
        else {
            Write-Host "✓ Repository is in sync with NinjaOne" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "An error occurred: $_"
        exit 1
    }
}

end {
    Write-Host "`nSync completed." -ForegroundColor Cyan
    exit 0
}

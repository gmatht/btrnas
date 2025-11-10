# PowerShell script to backup C:\Users to Samba share using robocopy
# This script uses Windows built-in robocopy for efficient file synchronization

param(
    [string]$DestinationShare = "",
    [string]$Username = "",
    [string]$Password = "",
    [int]$IntervalMinutes = 5,
    [switch]$Continuous,
    [string]$LogFile = "$PSScriptRoot\backup_log.txt"
)

# Configuration
$SourceDir = "C:\Users"
$ScriptDir = $PSScriptRoot

# Function to write log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage -ErrorAction SilentlyContinue
}

# Function to test network connection
function Test-NetworkShare {
    param([string]$SharePath)
    
    try {
        $TestPath = Join-Path $SharePath "test_write_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"
        $TestFile = New-Item -Path $TestPath -ItemType File -Force -ErrorAction Stop
        Remove-Item $TestFile -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}

# Function to map network drive if needed
function Map-NetworkDrive {
    param([string]$SharePath, [string]$Username, [string]$Password)
    
    # Extract server and share from UNC path
    if ($SharePath -match '^\\\\([^\\]+)\\(.+)$') {
        $Server = $Matches[1]
        $Share = $Matches[2]
        
        # Try to map drive
        if ($Username -and $Password) {
            $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
            $Credential = New-Object System.Management.Automation.PSCredential($Username, $SecurePassword)
            
            try {
                # Try to access share with credentials
                $MappedPath = "Z:"
                net use $MappedPath $SharePath /user:$Username $Password 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Successfully mapped network drive $MappedPath to $SharePath"
                    return $MappedPath
                }
            }
            catch {
                Write-Log "Failed to map network drive: $_" "ERROR"
            }
        }
    }
    
    return $null
}

# Main backup function
function Start-Backup {
    param([string]$Source, [string]$Destination)
    
    Write-Log "Starting backup from $Source to $Destination"
    
    # Robocopy options:
    # /E - Copy subdirectories, including empty ones
    # /COPYALL - Copy all file information (D=Data, A=Attributes, T=Timestamps, S=Security, O=Owner, U=Auditing info)
    # /R:3 - Retry 3 times on failed copies
    # /W:5 - Wait 5 seconds between retries
    # /MT:8 - Multi-threaded with 8 threads
    # /NP - No progress (reduces log size)
    # /NDL - No directory list
    # /NFL - No file list
    # /XD - Exclude directories (temp files, cache, etc.)
    
    $ExcludeDirs = @(
        "AppData\Local\Temp",
        "AppData\Local\Microsoft\Windows\INetCache",
        "AppData\Local\Microsoft\Windows\WebCache",
        "AppData\Roaming\Microsoft\Windows\Recent",
        "$Recycle.Bin",
        "AppData\Local\Packages\Microsoft.Windows.Search_cw5n1h2txyewy\TempState"
    )
    
    $RobocopyArgs = @(
        $Source,
        $Destination,
        "/E",
        "/COPYALL",
        "/R:3",
        "/W:5",
        "/MT:8",
        "/NP",
        "/NDL",
        "/NFL",
        "/LOG+:$LogFile"
    )
    
    # Add exclude directories
    foreach ($Dir in $ExcludeDirs) {
        $RobocopyArgs += "/XD"
        $RobocopyArgs += $Dir
    }
    
    # Run robocopy
    $RobocopyOutput = & robocopy @RobocopyArgs 2>&1
    $ExitCode = $LASTEXITCODE
    
    # Robocopy exit codes:
    # 0-7 = Success (0 = no changes, 1-7 = files copied)
    # 8+ = Error
    if ($ExitCode -le 7) {
        if ($ExitCode -eq 0) {
            Write-Log "Backup completed - no changes detected"
        }
        else {
            Write-Log "Backup completed successfully (Exit code: $ExitCode)"
        }
        return $true
    }
    else {
        Write-Log "Backup failed with exit code: $ExitCode" "ERROR"
        Write-Log "Robocopy output: $RobocopyOutput" "ERROR"
        return $false
    }
}

# Main execution
Write-Log "=== Backup Script Started ==="
Write-Log "Source: $SourceDir"

# Validate destination
if (-not $DestinationShare) {
    Write-Log "Error: Destination share not specified. Use -DestinationShare parameter or set in script." "ERROR"
    exit 1
}

Write-Log "Destination: $DestinationShare"

# Test network connection
Write-Log "Testing network connection to $DestinationShare..."
if (-not (Test-NetworkShare -SharePath $DestinationShare)) {
    Write-Log "Warning: Cannot write to destination share. Attempting to map drive..." "WARNING"
    
    if ($Username -and $Password) {
        $MappedDrive = Map-NetworkDrive -SharePath $DestinationShare -Username $Username -Password $Password
        if ($MappedDrive) {
            $DestinationShare = $MappedDrive
        }
    }
    else {
        Write-Log "Error: Cannot access share and no credentials provided." "ERROR"
        Write-Log "Please provide -Username and -Password parameters, or ensure the share is accessible." "ERROR"
        exit 1
    }
}

# Ensure destination directory exists
try {
    if (-not (Test-Path $DestinationShare)) {
        New-Item -Path $DestinationShare -ItemType Directory -Force | Out-Null
        Write-Log "Created destination directory: $DestinationShare"
    }
}
catch {
    Write-Log "Error creating destination directory: $_" "ERROR"
    exit 1
}

# Run backup
if ($Continuous) {
    Write-Log "Running in continuous mode (monitoring for changes)..."
    Write-Log "Press Ctrl+C to stop"
    
    # Use robocopy with /MON:1 to monitor for changes
    $RobocopyArgs = @(
        $SourceDir,
        $DestinationShare,
        "/E",
        "/COPYALL",
        "/R:3",
        "/W:5",
        "/MT:8",
        "/MON:1",
        "/MOT:1",
        "/NP",
        "/NDL",
        "/NFL",
        "/LOG+:$LogFile"
    )
    
    # Add exclude directories
    $ExcludeDirs = @(
        "AppData\Local\Temp",
        "AppData\Local\Microsoft\Windows\INetCache",
        "AppData\Local\Microsoft\Windows\WebCache",
        "AppData\Roaming\Microsoft\Windows\Recent",
        "$Recycle.Bin",
        "AppData\Local\Packages\Microsoft.Windows.Search_cw5n1h2txyewy\TempState"
    )
    
    foreach ($Dir in $ExcludeDirs) {
        $RobocopyArgs += "/XD"
        $RobocopyArgs += $Dir
    }
    
    try {
        & robocopy @RobocopyArgs
    }
    catch {
        Write-Log "Error in continuous mode: $_" "ERROR"
        exit 1
    }
}
else {
    Write-Log "Running scheduled backup (every $IntervalMinutes minutes)..."
    
    while ($true) {
        $Success = Start-Backup -Source $SourceDir -Destination $DestinationShare
        
        if (-not $Success) {
            Write-Log "Backup failed. Will retry in $IntervalMinutes minutes." "WARNING"
        }
        
        Write-Log "Waiting $IntervalMinutes minutes until next backup..."
        Start-Sleep -Seconds ($IntervalMinutes * 60)
    }
}



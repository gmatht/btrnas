# Installation script for Windows Users Backup to Samba
# This script sets up the backup solution and creates a scheduled task

param(
    [switch]$Uninstall
)

# Check if running as administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Error: This script must be run as Administrator" -ForegroundColor Red
    Write-Host "Right-click and select 'Run as administrator'" -ForegroundColor Yellow
    exit 1
}

$ScriptDir = $PSScriptRoot
$BackupScript = Join-Path $ScriptDir "backup_users_to_samba.ps1"
$TaskName = "WindowsUsersBackupToSamba"

if ($Uninstall) {
    Write-Host "Uninstalling scheduled task..." -ForegroundColor Yellow
    
    $Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($Task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Scheduled task removed successfully." -ForegroundColor Green
    }
    else {
        Write-Host "Scheduled task not found." -ForegroundColor Yellow
    }
    
    exit 0
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Windows Users Backup to Samba Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify backup script exists
if (-not (Test-Path $BackupScript)) {
    Write-Host "Error: Backup script not found at $BackupScript" -ForegroundColor Red
    exit 1
}

Write-Host "[1/5] Backup script found: $BackupScript" -ForegroundColor Green
Write-Host ""

# Step 2: Get configuration from user
Write-Host "[2/5] Configuration" -ForegroundColor Cyan
Write-Host ""

$DestinationShare = Read-Host "Enter Samba share path (e.g., \\server\btrfs\backups\users)"

if (-not $DestinationShare) {
    Write-Host "Error: Destination share is required" -ForegroundColor Red
    exit 1
}

# Validate UNC path format
if (-not ($DestinationShare -match '^\\\\')) {
    Write-Host "Warning: Path should start with \\\\ (UNC format)" -ForegroundColor Yellow
    $Continue = Read-Host "Continue anyway? (y/n)"
    if ($Continue -ne "y") {
        exit 1
    }
}

Write-Host ""
$UseCredentials = Read-Host "Do you need to provide credentials? (y/n)"

$Username = ""
$Password = ""

if ($UseCredentials -eq "y") {
    $Username = Read-Host "Enter Samba username"
    
    if ($Username) {
        $SecurePassword = Read-Host "Enter Samba password" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
        $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }
}

Write-Host ""
Write-Host "Backup method:" -ForegroundColor Cyan
Write-Host "  1. Scheduled (runs every N minutes) - Recommended"
Write-Host "  2. Continuous (monitors for changes continuously)"
$BackupMethod = Read-Host "Select method (1 or 2)"

$IntervalMinutes = 5
$Continuous = $false

if ($BackupMethod -eq "1") {
    $IntervalInput = Read-Host "Enter interval in minutes (default: 5)"
    if ($IntervalInput) {
        $IntervalMinutes = [int]$IntervalInput
    }
}
elseif ($BackupMethod -eq "2") {
    $Continuous = $true
}
else {
    Write-Host "Invalid selection. Using scheduled method with 5 minute interval." -ForegroundColor Yellow
}

Write-Host ""

# Step 3: Test network connection
Write-Host "[3/5] Testing network connection..." -ForegroundColor Cyan

try {
    $TestPath = Join-Path $DestinationShare "test_write_$(Get-Date -Format 'yyyyMMddHHmmss').tmp"
    $TestFile = New-Item -Path $TestPath -ItemType File -Force -ErrorAction Stop
    Remove-Item $TestFile -Force -ErrorAction SilentlyContinue
    Write-Host "Network connection test successful!" -ForegroundColor Green
}
catch {
    Write-Host "Warning: Cannot write to destination share: $_" -ForegroundColor Yellow
    Write-Host "The backup will attempt to use credentials when running." -ForegroundColor Yellow
}

Write-Host ""

# Step 4: Create scheduled task
Write-Host "[4/5] Creating scheduled task..." -ForegroundColor Cyan

# Remove existing task if it exists
$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($ExistingTask) {
    Write-Host "Removing existing task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Build PowerShell command
$PsCommand = "& '$BackupScript'"
$PsCommand += " -DestinationShare '$DestinationShare'"

# Note: For better security, consider mapping the drive with persistent credentials:
# net use Z: $DestinationShare /user:$Username /persistent:yes
# Then use Z: as the destination instead

if ($Username) {
    Write-Host "Note: Credentials will be stored in the scheduled task." -ForegroundColor Yellow
    Write-Host "For better security, consider mapping the drive first:" -ForegroundColor Yellow
    Write-Host "  net use Z: $DestinationShare /user:$Username /persistent:yes" -ForegroundColor Cyan
    Write-Host ""
    $UseMappedDrive = Read-Host "Have you mapped the drive? Use mapped drive instead? (y/n)"
    
    if ($UseMappedDrive -eq "y") {
        $MappedDrive = Read-Host "Enter mapped drive letter (e.g., Z:)"
        $DestinationShare = $MappedDrive
        $Username = ""
        $Password = ""
    }
    else {
        $PsCommand += " -Username '$Username'"
        $PsCommand += " -Password '$Password'"
    }
}

if ($Continuous) {
    $PsCommand += " -Continuous"
}
else {
    $PsCommand += " -IntervalMinutes $IntervalMinutes"
}

# Create action
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command $PsCommand"

# Create trigger (at startup)
$Trigger = New-ScheduledTaskTrigger -AtStartup

# Create settings
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable

# Create principal (run as SYSTEM or current user)
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Highest

# Register the task
try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "Backup C:\Users to Samba share" | Out-Null
    Write-Host "Scheduled task created successfully!" -ForegroundColor Green
}
catch {
    Write-Host "Error creating scheduled task: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 5: Summary
Write-Host "[5/5] Setup Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Task Name: $TaskName"
Write-Host "  Source: C:\Users"
Write-Host "  Destination: $DestinationShare"
if ($Continuous) {
    Write-Host "  Method: Continuous monitoring"
}
else {
    Write-Host "  Method: Scheduled (every $IntervalMinutes minutes)"
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Test the backup manually:"
Write-Host "     powershell.exe -ExecutionPolicy Bypass -File `"$BackupScript`" -DestinationShare `"$DestinationShare`""
Write-Host ""
Write-Host "  2. Start the scheduled task:"
Write-Host "     Start-ScheduledTask -TaskName `"$TaskName`""
Write-Host ""
Write-Host "  3. Check task status:"
Write-Host "     Get-ScheduledTask -TaskName `"$TaskName`" | Get-ScheduledTaskInfo"
Write-Host ""
Write-Host "  4. View logs:"
Write-Host "     Get-Content `"$ScriptDir\backup_log.txt`" -Tail 50"
Write-Host ""
Write-Host "  5. To uninstall, run:"
Write-Host "     .\install_windows_backup.ps1 -Uninstall"
Write-Host ""


# PowerShell script to create a new partition on the same disk as the bootfs volume
# This script finds the boot/EFI partition, identifies its disk, and creates a new partition

#Requires -RunAsAdministrator

# Function to print colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

Write-Status "Starting partition setup for bootfs volume disk"
Write-Warning "This script will modify partitions. Make sure you have a backup!"

# Find the boot/EFI partition
Write-Status "Searching for boot/EFI partition..."

$bootPartition = $null
$bootDisk = $null

# Method 1: Look for EFI System Partition
$efiPartition = Get-Partition | Where-Object {
    $_.Type -eq 'System' -or 
    $_.GptType -eq '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}' -or
    ($_.DriveLetter -eq $null -and $_.Size -lt 1GB)
} | Select-Object -First 1

if ($efiPartition) {
    $bootPartition = $efiPartition
    Write-Status "Found EFI System Partition: Partition $($efiPartition.PartitionNumber) on Disk $($efiPartition.DiskNumber)"
}

# Method 2: Look for System Reserved partition (older Windows)
if (-not $bootPartition) {
    $systemReserved = Get-Partition | Where-Object {
        $_.Type -eq 'System' -or
        ($_.DriveLetter -eq $null -and $_.Size -lt 500MB)
    } | Select-Object -First 1
    
    if ($systemReserved) {
        $bootPartition = $systemReserved
        Write-Status "Found System Reserved Partition: Partition $($systemReserved.PartitionNumber) on Disk $($systemReserved.DiskNumber)"
    }
}

# Method 3: Look for partition with Windows boot files
if (-not $bootPartition) {
    $bootVolumes = Get-Volume | Where-Object {
        $_.DriveLetter -ne $null -and
        (Test-Path "$($_.DriveLetter):\Windows\System32\winload.exe" -ErrorAction SilentlyContinue)
    }
    
    if ($bootVolumes) {
        $bootVolume = $bootVolumes | Select-Object -First 1
        $bootPartition = Get-Partition -DriveLetter $bootVolume.DriveLetter
        Write-Status "Found Windows Boot Volume: Drive $($bootVolume.DriveLetter) on Disk $($bootPartition.DiskNumber)"
    }
}

if (-not $bootPartition) {
    Write-Error "Could not find boot/EFI partition. Exiting."
    exit 1
}

$bootDisk = Get-Disk -Number $bootPartition.DiskNumber

if (-not $bootDisk) {
    Write-Error "Could not determine boot disk"
    exit 1
}

Write-Status "Boot disk identified: Disk $($bootDisk.Number) - $($bootDisk.FriendlyName)"
Write-Status "Disk size: $([math]::Round($bootDisk.Size / 1GB, 2)) GB"
Write-Status "Partition style: $($bootDisk.PartitionStyle)"

# Get all partitions on the boot disk
$partitions = Get-Partition -DiskNumber $bootDisk.Number | Sort-Object PartitionNumber
Write-Status "Current partitions on Disk $($bootDisk.Number):"
$partitions | Format-Table PartitionNumber, DriveLetter, Size, Type, GptType -AutoSize

# Find the last partition to determine where to create the new one
$lastPartition = $partitions | Sort-Object PartitionNumber -Descending | Select-Object -First 1
if (-not $lastPartition) {
    Write-Error "No partitions found on disk"
    exit 1
}

# Calculate unallocated space
$allocatedSize = ($partitions | Measure-Object -Property Size -Sum).Sum
$unallocatedSize = $bootDisk.Size - $allocatedSize
$unallocatedGB = [math]::Round($unallocatedSize / 1GB, 2)

Write-Status "Unallocated space: $unallocatedGB GB"

if ($unallocatedSize -lt 100MB) {
    Write-Error "Insufficient unallocated space ($unallocatedGB GB). Need at least 100 MB."
    exit 1
}

# Use all available unallocated space automatically
$partitionSize = $unallocatedSize
Write-Status "Using all available space: $unallocatedGB GB"

# Use FAT32 by default to prevent Raspbian from automatically taking up the space
$filesystem = "FAT32"
Write-Status "Using filesystem: $filesystem (prevents Raspbian from auto-claiming space)"

# Automatically assign a drive letter if available
$driveLetter = $null
$availableLetters = 70..90 | ForEach-Object { [char]$_ } | Where-Object {
    $letter = $_
    $existing = Get-Partition | Where-Object { $_.DriveLetter -eq $letter }
    -not $existing
}

if ($availableLetters) {
    $driveLetter = $availableLetters[0]
    Write-Status "Will assign drive letter: $driveLetter"
} else {
    Write-Status "No available drive letters, partition will be created without assignment"
}

# Get the offset for the new partition (after the last partition)
$lastPartitionEnd = $lastPartition.Offset + $lastPartition.Size
$newPartitionOffset = $lastPartitionEnd

Write-Status "Creating new partition starting at offset: $([math]::Round($newPartitionOffset / 1GB, 2)) GB"

# Create the partition
try {
    if ($bootDisk.PartitionStyle -eq "GPT") {
        Write-Status "Creating GPT partition..."
        $newPartition = New-Partition -DiskNumber $bootDisk.Number `
            -Offset $newPartitionOffset `
            -Size $partitionSize `
            -GptType '{EBD0A0A2-B9E5-4433-87C0-68B6B72699C7}'  # Basic data partition GUID
    } else {
        Write-Status "Creating MBR partition..."
        $newPartition = New-Partition -DiskNumber $bootDisk.Number `
            -Offset $newPartitionOffset `
            -Size $partitionSize
    }
    
    Write-Status "Partition created: Partition $($newPartition.PartitionNumber)"
    
    # Assign drive letter if requested
    if ($driveLetter) {
        Write-Status "Assigning drive letter $driveLetter..."
        $newPartition | Set-Partition -NewDriveLetter $driveLetter
        $newPartition = Get-Partition -DiskNumber $bootDisk.Number -PartitionNumber $newPartition.PartitionNumber
    }
    
    # Format the partition as FAT32
    Write-Status "Formatting partition as FAT32..."
    
    $formatParams = @{
        Partition = $newPartition
        FileSystem = "FAT32"
        Confirm = $false
        Force = $true
    }
    
    Format-Volume @formatParams
    
    # Refresh partition info
    $newPartition = Get-Partition -DiskNumber $bootDisk.Number -PartitionNumber $newPartition.PartitionNumber
    $volume = $newPartition | Get-Volume
    
    Write-Status "Partition formatted successfully!"
    Write-Host ""
    Write-Status "=== New Partition Information ==="
    Write-Host "Partition Number: $($newPartition.PartitionNumber)"
    Write-Host "Drive Letter: $(if ($newPartition.DriveLetter) { $newPartition.DriveLetter } else { 'None' })"
    Write-Host "Size: $([math]::Round($newPartition.Size / 1GB, 2)) GB"
    Write-Host "File System: $($volume.FileSystemType)"
    Write-Host "Volume Label: $(if ($volume.FileSystemLabel) { $volume.FileSystemLabel } else { 'None' })"
    Write-Host "Volume GUID: $($volume.UniqueId)"
    
    if ($newPartition.DriveLetter) {
        Write-Status "Partition is ready at: $($newPartition.DriveLetter):\"
    } else {
        Write-Status "Partition created but not assigned a drive letter. You can assign one later using Disk Management."
    }
    
} catch {
    Write-Error "Failed to create partition: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}

Write-Status "Setup completed successfully!"

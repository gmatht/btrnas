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

Write-Status "Starting partition setup for Raspberry Pi bootfs (SD card)"
Write-Warning "This script will modify partitions on the SD card. Make sure you have a backup!"

# Function to search for bootfs partition
function Find-BootfsPartition {
    $foundPartition = $null
    
    # Method 1: Look for removable drives with VFAT/FAT32 partitions that have Raspberry Pi bootfs characteristics
    $removableDisks = Get-Disk | Where-Object { $_.BusType -eq 'USB' -or $_.MediaType -eq 'RemovableMedia' }
    
    foreach ($disk in $removableDisks) {
        $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
        foreach ($partition in $partitions) {
            if ($partition.DriveLetter) {
                $volume = Get-Volume -DriveLetter $partition.DriveLetter -ErrorAction SilentlyContinue
                if ($volume -and ($volume.FileSystemType -eq 'FAT32' -or $volume.FileSystemType -eq 'FAT')) {
                    $drivePath = "$($partition.DriveLetter):\"
                    # Check for Raspberry Pi bootfs characteristics
                    if ((Test-Path "$drivePath\config.txt" -ErrorAction SilentlyContinue) -or
                        (Test-Path "$drivePath\firmware" -ErrorAction SilentlyContinue) -or
                        (Test-Path "$drivePath\boot" -ErrorAction SilentlyContinue)) {
                        $foundPartition = $partition
                        Write-Status "Found Raspberry Pi bootfs partition: Drive $($partition.DriveLetter) on Disk $($disk.Number)"
                        return $foundPartition
                    }
                }
            }
        }
    }
    
    # Method 2: Look for any VFAT/FAT32 partition with Raspberry Pi bootfs characteristics (not on fixed disks)
    $allPartitions = Get-Partition | Where-Object { $_.DriveLetter -ne $null }
    
    foreach ($partition in $allPartitions) {
        $disk = Get-Disk -Number $partition.DiskNumber
        # Skip fixed/internal disks (prioritize removable)
        if ($disk.BusType -eq 'USB' -or $disk.MediaType -eq 'RemovableMedia' -or 
            ($disk.BusType -ne 'SATA' -and $disk.BusType -ne 'ATA' -and $disk.BusType -ne 'NVMe')) {
            $volume = Get-Volume -DriveLetter $partition.DriveLetter -ErrorAction SilentlyContinue
            if ($volume -and ($volume.FileSystemType -eq 'FAT32' -or $volume.FileSystemType -eq 'FAT')) {
                $drivePath = "$($partition.DriveLetter):\"
                # Check for Raspberry Pi bootfs characteristics
                if ((Test-Path "$drivePath\config.txt" -ErrorAction SilentlyContinue) -or
                    (Test-Path "$drivePath\firmware" -ErrorAction SilentlyContinue) -or
                    (Test-Path "$drivePath\boot" -ErrorAction SilentlyContinue)) {
                    $foundPartition = $partition
                    Write-Status "Found Raspberry Pi bootfs partition: Drive $($partition.DriveLetter) on Disk $($disk.Number)"
                    return $foundPartition
                }
            }
        }
    }
    
    # Method 3: If still not found, look for any small VFAT partition (might be unmounted bootfs)
    foreach ($disk in $removableDisks) {
        $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
        foreach ($partition in $partitions) {
            # Look for small VFAT partitions (typical bootfs size is 256MB-512MB)
            if ($partition.Size -ge 200MB -and $partition.Size -le 2GB) {
                # Try to get volume info
                try {
                    $volume = $partition | Get-Volume -ErrorAction SilentlyContinue
                    if ($volume -and ($volume.FileSystemType -eq 'FAT32' -or $volume.FileSystemType -eq 'FAT')) {
                        $foundPartition = $partition
                        Write-Status "Found potential bootfs partition: Partition $($partition.PartitionNumber) on Disk $($disk.Number)"
                        return $foundPartition
                    }
                } catch {
                    # Partition might not be mounted, but could still be bootfs
                    if ($partition.DriveLetter -eq $null) {
                        $foundPartition = $partition
                        Write-Status "Found unmounted partition on removable disk: Partition $($partition.PartitionNumber) on Disk $($disk.Number)"
                        return $foundPartition
                    }
                }
            }
        }
    }
    
    return $null
}

# Try to find bootfs partition (with retry option)
Write-Status "Searching for Raspberry Pi bootfs partition (VFAT/FAT32 on SD card)..."
$maxRetries = 2
$retryCount = 0
$bootPartition = $null
$bootDisk = $null

while ($retryCount -le $maxRetries) {
    if ($retryCount -eq 0) {
        # First attempt
        $bootPartition = Find-BootfsPartition
    } else {
        # Retry after user reinserts SD card
        Write-Host ""
        Write-Status "Retrying search for bootfs partition..."
        Start-Sleep -Seconds 2
        $bootPartition = Find-BootfsPartition
    }
    
    if ($bootPartition) {
        break
    }
    
    if ($retryCount -lt $maxRetries) {
        Write-Host ""
        Write-Warning "Could not find Raspberry Pi bootfs partition."
        Write-Host ""
        Write-Host "This may happen if:"
        Write-Host "  - The SD card was just written and needs to be re-mounted"
        Write-Host "  - Windows hasn't recognized the partitions yet"
        Write-Host ""
        Write-Host "Available removable disks:"
        Get-Disk | Where-Object { $_.BusType -eq 'USB' -or $_.MediaType -eq 'RemovableMedia' } | Format-Table Number, FriendlyName, Size, PartitionStyle
        Write-Host ""
        Write-Warning "Please remove and reinsert the microSD card, then press any key to retry..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $retryCount++
    } else {
        Write-Host ""
        Write-Error "Could not find Raspberry Pi bootfs partition after $($maxRetries + 1) attempts."
        Write-Error ""
        Write-Error "Please make sure:"
        Write-Error "  1. The SD card is inserted"
        Write-Error "  2. The SD card has been written with Raspberry Pi OS"
        Write-Error "  3. The bootfs partition is accessible"
        Write-Error "  4. You have removed and reinserted the SD card"
        Write-Host ""
        Write-Host "Available removable disks:"
        Get-Disk | Where-Object { $_.BusType -eq 'USB' -or $_.MediaType -eq 'RemovableMedia' } | Format-Table Number, FriendlyName, Size, PartitionStyle
        exit 1
    }
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

# Calculate unallocated space more accurately
$allocatedSize = ($partitions | Measure-Object -Property Size -Sum).Sum
$unallocatedSize = $bootDisk.Size - $allocatedSize
$unallocatedGB = [math]::Round($unallocatedSize / 1GB, 2)

Write-Status "Unallocated space: $unallocatedGB GB"

# Also check using Get-PartitionSupportedSize for more accurate available space
try {
    $supportedSize = Get-PartitionSupportedSize -DiskNumber $bootDisk.Number -PartitionNumber $lastPartition.PartitionNumber
    $actualMaxSize = $supportedSize.SizeMax
    $actualMaxSizeGB = [math]::Round($actualMaxSize / 1GB, 2)
    
    if ($actualMaxSize -lt $unallocatedSize) {
        Write-Warning "Actual available space ($actualMaxSizeGB GB) is less than calculated unallocated space ($unallocatedGB GB)"
        Write-Status "Using actual available space: $actualMaxSizeGB GB"
        $unallocatedSize = $actualMaxSize
        $unallocatedGB = $actualMaxSizeGB
    }
} catch {
    Write-Warning "Could not determine actual available space, using calculated value"
}

if ($unallocatedSize -lt 100MB) {
    Write-Error "Insufficient unallocated space ($unallocatedGB GB). Need at least 100 MB."
    Write-Error "The disk may be full or there may be partition alignment issues."
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
    # Verify we have enough space before attempting
    if ($partitionSize -gt $unallocatedSize) {
        Write-Warning "Requested size exceeds available space. Adjusting to maximum available."
        $partitionSize = $unallocatedSize
    }
    
    # For MBR, we might need to use a smaller size or different approach
    if ($bootDisk.PartitionStyle -eq "MBR") {
        # MBR has limitations - try using maximum available size instead of specific offset/size
        Write-Status "Creating MBR partition (using maximum available space)..."
        try {
            $newPartition = New-Partition -DiskNumber $bootDisk.Number `
                -UseMaximumSize `
                -AssignDriveLetter:$false
        } catch {
            # Fallback to specific offset/size
            Write-Status "Trying with specific offset and size..."
            $newPartition = New-Partition -DiskNumber $bootDisk.Number `
                -Offset $newPartitionOffset `
                -Size $partitionSize `
                -ErrorAction Stop
        }
    } else {
        Write-Status "Creating GPT partition..."
        $newPartition = New-Partition -DiskNumber $bootDisk.Number `
            -Offset $newPartitionOffset `
            -Size $partitionSize `
            -GptType '{EBD0A0A2-B9E5-4433-87C0-68B6B72699C7}' `
            -ErrorAction Stop
    }
    
    # Verify partition was actually created
    if (-not $newPartition) {
        throw "Partition creation returned null"
    }
    
    if (-not $newPartition.PartitionNumber) {
        throw "Partition was created but has no partition number"
    }
    
    Write-Status "Partition created: Partition $($newPartition.PartitionNumber)"
    
    # Refresh partition info to get latest state
    Start-Sleep -Seconds 1
    $newPartition = Get-Partition -DiskNumber $bootDisk.Number -PartitionNumber $newPartition.PartitionNumber -ErrorAction Stop
    
    # Assign drive letter if requested
    if ($driveLetter -and $newPartition) {
        Write-Status "Assigning drive letter $driveLetter..."
        try {
            $newPartition | Set-Partition -NewDriveLetter $driveLetter -ErrorAction Stop
            $newPartition = Get-Partition -DiskNumber $bootDisk.Number -PartitionNumber $newPartition.PartitionNumber -ErrorAction Stop
        } catch {
            Write-Warning "Could not assign drive letter ${driveLetter}: $($_.Exception.Message)"
            Write-Status "Partition created but without drive letter assignment"
        }
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
    
    if ($_.Exception.Message -like "*Not enough available capacity*" -or 
        $_.Exception.Message -like "*insufficient*" -or
        $_.Exception.Message -like "*capacity*") {
        Write-Error ""
        Write-Error "The partition could not be created due to insufficient space."
        Write-Error "Possible causes:"
        Write-Error "  1. The disk is actually full"
        Write-Error "  2. Partition alignment issues"
        Write-Error "  3. The calculated unallocated space may be incorrect"
        Write-Error ""
        Write-Error "Try:"
        Write-Error "  - Resizing existing partitions to free up space"
        Write-Error "  - Using diskpart or Disk Management to check actual free space"
        Write-Error "  - The partition may already exist - check Disk Management"
    }
    
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}

Write-Status "Setup completed successfully!"

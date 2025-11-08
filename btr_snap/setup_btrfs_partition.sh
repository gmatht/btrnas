#!/bin/bash
# Script to resize mmcblk0p2 to a user-specified size (default: 3G) and create a new BTRFS partition
# This script checks for and removes mmcblk0p3 and mmcblk0p4 if they exist,
# then resizes p2 to the specified size and creates a new partition filling the rest of the disk

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Device and partition variables
DEVICE="/dev/mmcblk0"
PART2="${DEVICE}p2"
PART3="${DEVICE}p3"
PART4="${DEVICE}p4"
MOUNT_POINT="/btrfs"

# Check if device exists
if [[ ! -b "$DEVICE" ]]; then
    print_error "Device $DEVICE does not exist"
    exit 1
fi

# Function to install missing tools
install_tool() {
    local tool=$1
    local package=$2
    
    if ! command -v $tool &> /dev/null; then
        print_warning "$tool not found. Attempting to install $package..."
        
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y "$package"
        elif command -v yum &> /dev/null; then
            yum install -y "$package"
        elif command -v dnf &> /dev/null; then
            dnf install -y "$package"
        elif command -v pacman &> /dev/null; then
            pacman -S --noconfirm "$package"
        else
            print_error "Could not install $package automatically. Please install it manually."
            return 1
        fi
        
        # Verify installation
        if command -v $tool &> /dev/null; then
            print_status "$tool installed successfully"
            return 0
        else
            print_error "Failed to install $tool"
            return 1
        fi
    fi
    return 0
}

print_status "Starting partition setup for $DEVICE"
print_warning "This script will modify partitions on $DEVICE. Make sure you have a backup!"

# First, check for and install parted (needed for resizing partition 2)
print_status "Checking for parted (required for partition resizing)..."
if ! install_tool "parted" "parted"; then
    print_error "parted is required but could not be installed"
    exit 1
fi

# Prompt for partition 2 size
echo
print_status "Partition 2 (mmcblk0p2) will be resized BEFORE installing other tools."
echo -n "Enter the desired size for partition 2 (default: 3G): "
read -r PART2_SIZE_INPUT

# Use default if empty
if [[ -z "$PART2_SIZE_INPUT" ]]; then
    PART2_SIZE_INPUT="3G"
fi

# Normalize the input (add 'iB' suffix if not present and it's a valid format)
# Check if it already has a unit suffix
if [[ "$PART2_SIZE_INPUT" =~ ^[0-9]+[KMGT]?i?B?$ ]]; then
    # If it ends with just G, M, K, T, add 'iB' for parted compatibility
    if [[ "$PART2_SIZE_INPUT" =~ ^[0-9]+[KMGT]$ ]]; then
        PART2_TARGET_SIZE="${PART2_SIZE_INPUT}iB"
    else
        PART2_TARGET_SIZE="$PART2_SIZE_INPUT"
    fi
else
    print_error "Invalid size format. Please use formats like: 3G, 3GiB, 4096M, etc."
    exit 1
fi

print_status "Partition 2 will be resized to: $PART2_TARGET_SIZE"

# Check if PART3 or PART4 exist
PART3_EXISTS=false
PART4_EXISTS=false

if [[ -b "$PART3" ]]; then
    PART3_EXISTS=true
    print_status "Found $PART3"
fi

if [[ -b "$PART4" ]]; then
    PART4_EXISTS=true
    print_status "Found $PART4"
fi

# Function to show partition information
show_partition_info() {
    local part=$1
    local part_num=$2
    
    if [[ ! -b "$part" ]]; then
        return
    fi
    
    print_status "=== Information for $part ==="
    
    # Check if partition is mounted
    local mount_point=$(mount | grep "$part" | awk '{print $3}' | head -n1)
    local temp_mount=""
    
    if [[ -n "$mount_point" ]]; then
        print_status "Partition is mounted at: $mount_point"
        temp_mount="$mount_point"
    else
        # Create temporary mount point
        temp_mount=$(mktemp -d)
        print_status "Mounting $part temporarily to $temp_mount for inspection..."
        
        # Try to mount (may fail if filesystem is unknown or corrupted)
        if mount "$part" "$temp_mount" 2>/dev/null; then
            print_status "Successfully mounted for inspection"
        else
            print_warning "Could not mount $part (may be unformatted or have unknown filesystem)"
            rmdir "$temp_mount" 2>/dev/null || true
            temp_mount=""
        fi
    fi
    
    if [[ -n "$temp_mount" ]] && [[ -d "$temp_mount" ]]; then
        # Show disk usage
        print_status "Disk usage:"
        df -h "$part" | tail -n1
        
        # List files (top level only, with sizes if possible)
        print_status "Files and directories in root of partition:"
        if ls -lah "$temp_mount" 2>/dev/null | head -n20; then
            local file_count=$(find "$temp_mount" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
            print_status "Total items in root: $file_count"
        else
            print_warning "Could not list files"
        fi
        
        # Show total size used
        print_status "Total space used:"
        du -sh "$temp_mount" 2>/dev/null || print_warning "Could not calculate total size"
        
        # Unmount if we mounted it temporarily (only if it wasn't already mounted)
        if [[ -z "$mount_point" ]] && [[ -n "$temp_mount" ]]; then
            print_status "Unmounting temporary mount..."
            umount "$temp_mount" 2>/dev/null || true
            rmdir "$temp_mount" 2>/dev/null || true
        fi
    else
        # Show partition info even if we can't mount it
        print_status "Partition size information:"
        parted -s "$DEVICE" unit MiB print | grep "^ $part_num" || true
        lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "$part" 2>/dev/null || true
    fi
    
    echo
}

# If either partition exists, show information and ask for confirmation
if [[ "$PART3_EXISTS" == true ]] || [[ "$PART4_EXISTS" == true ]]; then
    print_warning "Partitions p3 and/or p4 exist and will be DELETED!"
    echo
    
    # Show information for each partition
    if [[ "$PART3_EXISTS" == true ]]; then
        show_partition_info "$PART3" "3"
    fi
    
    if [[ "$PART4_EXISTS" == true ]]; then
        show_partition_info "$PART4" "4"
    fi
    
    # Ask for user confirmation
    print_warning "WARNING: This will PERMANENTLY DELETE the above partition(s) and all their data!"
    echo -n "Do you want to proceed? (type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        print_error "Operation cancelled by user"
        exit 1
    fi
    
    print_status "User confirmed. Proceeding with deletion..."
    
    # Now unmount partitions if they are mounted
    print_status "Unmounting partitions if mounted..."
    for part in "$PART3" "$PART4"; do
        if mountpoint -q "$part" 2>/dev/null || grep -q "$part" /proc/mounts; then
            print_warning "Unmounting $part..."
            umount "$part" 2>/dev/null || true
        fi
    done
    
    # Also check for any mount points that might be using these partitions
    for mount_info in $(mount | grep -E "(mmcblk0p3|mmcblk0p4)" | awk '{print $1" "$3}'); do
        part=$(echo "$mount_info" | awk '{print $1}')
        mount_pt=$(echo "$mount_info" | awk '{print $2}')
        if [[ "$part" == "$PART3" ]] || [[ "$part" == "$PART4" ]]; then
            print_warning "Unmounting $part from $mount_pt..."
            umount "$mount_pt" 2>/dev/null || true
        fi
    done
    
    print_status "Partitions p3 or p4 exist. Proceeding with deletion and resize..."
    
    # Get current partition table info
    print_status "Reading current partition table..."
    
    # Get the end sector of partition 2
    PART2_END=$(parted -s "$DEVICE" unit s print | grep "^ 2" | awk '{print $3}' | sed 's/s$//')
    
    if [[ -z "$PART2_END" ]]; then
        print_error "Could not determine end of partition 2"
        exit 1
    fi
    
    print_status "Partition 2 currently ends at sector $PART2_END"
    
    # Use parted's human-readable sizes
    print_status "Resizing partition 2 to $PART2_TARGET_SIZE..."
    
    # Delete partitions 3 and 4 if they exist (in reverse order)
    if [[ "$PART4_EXISTS" == true ]]; then
        print_status "Deleting partition 4..."
        parted -s "$DEVICE" rm 4 || print_warning "Failed to delete partition 4 (may not exist in partition table)"
    fi
    
    if [[ "$PART3_EXISTS" == true ]]; then
        print_status "Deleting partition 3..."
        parted -s "$DEVICE" rm 3 || print_warning "Failed to delete partition 3 (may not exist in partition table)"
    fi
    
    # Resize partition 2
    print_status "Resizing partition 2 to $PART2_TARGET_SIZE..."
    parted -s "$DEVICE" resizepart 2 "$PART2_TARGET_SIZE"
    
    # Get the new end of partition 2
    NEW_PART2_END_SECTOR=$(parted -s "$DEVICE" unit s print | grep "^ 2" | awk '{print $3}' | sed 's/s$//')
    print_status "Partition 2 now ends at sector $NEW_PART2_END_SECTOR"
    
else
    print_status "Partitions p3 and p4 do not exist. Checking if partition 2 needs resizing..."
    
    # Get current size of partition 2
    PART2_CURRENT_SIZE=$(parted -s "$DEVICE" unit MiB print | grep "^ 2" | awk '{print $4}' | sed 's/MiB$//')
    
    if [[ -z "$PART2_CURRENT_SIZE" ]]; then
        print_error "Could not determine size of partition 2"
        exit 1
    fi
    
    # Always resize to target size (parted will handle if it's already that size or larger)
    print_status "Current partition 2 size: ${PART2_CURRENT_SIZE}MiB"
    print_status "Resizing partition 2 to $PART2_TARGET_SIZE..."
    parted -s "$DEVICE" resizepart 2 "$PART2_TARGET_SIZE"
fi

print_status "Partition 2 resizing completed."

# Now install remaining required tools
echo
print_status "Installing remaining required tools..."

# Check for mkfs.btrfs (btrfs-progs package)
if ! install_tool "mkfs.btrfs" "btrfs-progs"; then
    print_error "btrfs-progs is required but could not be installed"
    exit 1
fi

# Check for blkid (util-linux package)
if ! install_tool "blkid" "util-linux"; then
    print_error "util-linux is required but could not be installed"
    exit 1
fi

# Check for truncate (coreutils package) - needed if creating image file
if ! install_tool "truncate" "coreutils"; then
    print_warning "truncate (coreutils) is recommended but could not be installed"
    print_warning "Image file creation will fail if unpartitioned space is insufficient"
fi

# Get the end of partition 2 and disk size
print_status "Determining available space for new partition..."
DISK_SIZE=$(parted -s "$DEVICE" unit s print | grep "^Disk $DEVICE" | awk '{print $3}' | sed 's/s$//')
PART2_END_SECTOR=$(parted -s "$DEVICE" unit s print | grep "^ 2" | awk '{print $3}' | sed 's/s$//')

if [[ -z "$DISK_SIZE" ]] || [[ -z "$PART2_END_SECTOR" ]]; then
    print_error "Could not determine disk size or partition 2 end"
    exit 1
fi

# Calculate unpartitioned space in bytes (assuming 512 byte sectors)
UNPARTITIONED_SECTORS=$((DISK_SIZE - PART2_END_SECTOR))
UNPARTITIONED_BYTES=$((UNPARTITIONED_SECTORS * 512))
UNPARTITIONED_MB=$((UNPARTITIONED_BYTES / 1024 / 1024))

print_status "Unpartitioned space: ${UNPARTITIONED_MB}MB"

# Check if we have at least 100MB of unpartitioned space
USE_IMAGE_FILE=false
IMAGE_PATH=""
if [[ $UNPARTITIONED_MB -lt 100 ]]; then
    print_warning "Less than 100MB of unpartitioned space available (${UNPARTITIONED_MB}MB)"
    print_status "Will create btrfs.img file instead of a new partition"
    USE_IMAGE_FILE=true
fi

if [[ "$USE_IMAGE_FILE" == true ]]; then
    # Find root partition and get free space
    print_status "Finding root partition..."
    ROOT_PART=$(mount | grep " / " | awk '{print $1}' | head -n1)
    
    if [[ -z "$ROOT_PART" ]]; then
        # Try alternative method
        ROOT_PART=$(df / | tail -n1 | awk '{print $1}')
    fi
    
    if [[ -z "$ROOT_PART" ]]; then
        print_error "Could not determine root partition"
        exit 1
    fi
    
    print_status "Root partition: $ROOT_PART"
    
    # Get free space on root partition in bytes
    ROOT_FREE_BYTES=$(df -B1 / | tail -n1 | awk '{print $4}')
    
    if [[ -z "$ROOT_FREE_BYTES" ]]; then
        print_error "Could not determine free space on root partition"
        exit 1
    fi
    
    # Calculate 95% of free space
    IMAGE_SIZE=$((ROOT_FREE_BYTES * 95 / 100))
    IMAGE_SIZE_MB=$((IMAGE_SIZE / 1024 / 1024))
    
    print_status "Free space on root: $(df -h / | tail -n1 | awk '{print $4}')"
    print_status "Creating btrfs.img with size: ${IMAGE_SIZE_MB}MB (95% of free space)"
    
    # Determine where to create the image file (prefer /root or /home)
    IMAGE_PATH=""
    for dir in /root /home /opt; do
        if [[ -d "$dir" ]] && [[ -w "$dir" ]]; then
            IMAGE_PATH="$dir/btrfs.img"
            break
        fi
    done
    
    # Fallback to root if no writable directory found
    if [[ -z "$IMAGE_PATH" ]]; then
        IMAGE_PATH="/btrfs.img"
    fi
    
    print_status "Creating btrfs.img at: $IMAGE_PATH"
    
    # Create the image file using truncate
    truncate -s "$IMAGE_SIZE" "$IMAGE_PATH"
    
    if [[ ! -f "$IMAGE_PATH" ]]; then
        print_error "Failed to create btrfs.img file"
        exit 1
    fi
    
    print_status "Image file created: $IMAGE_PATH"
    
    # Format the image file as BTRFS
    print_status "Formatting $IMAGE_PATH as BTRFS..."
    mkfs.btrfs -f "$IMAGE_PATH"
    
    # Create mount point if it doesn't exist
    if [[ ! -d "$MOUNT_POINT" ]]; then
        print_status "Creating mount point $MOUNT_POINT..."
        mkdir -p "$MOUNT_POINT"
    fi
    
    # Get the UUID of the image file
    UUID=$(blkid -s UUID -o value "$IMAGE_PATH")
    
    if [[ -z "$UUID" ]]; then
        print_error "Could not determine UUID of image file"
        exit 1
    fi
    
    print_status "Image file UUID: $UUID"
    
    # Check if entry already exists in fstab
    if grep -q "$MOUNT_POINT" /etc/fstab; then
        print_warning "Entry for $MOUNT_POINT already exists in /etc/fstab"
        print_status "Backing up /etc/fstab to /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
        cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Remove old entry
        sed -i "\|$MOUNT_POINT|d" /etc/fstab
        print_status "Removed old entry from /etc/fstab"
    fi
    
    # Add entry to fstab with loop mount
    FSTAB_ENTRY="$IMAGE_PATH $MOUNT_POINT btrfs loop,noatime,compress=zstd:1 0 0"
    print_status "Adding entry to /etc/fstab:"
    echo "  $FSTAB_ENTRY"
    echo "$FSTAB_ENTRY" >> /etc/fstab
    
    # Mount the image file
    print_status "Mounting $IMAGE_PATH to $MOUNT_POINT..."
    mount "$MOUNT_POINT"
    
    # Verify mount
    if mountpoint -q "$MOUNT_POINT"; then
        print_status "Successfully mounted $IMAGE_PATH to $MOUNT_POINT"
        
        # Show filesystem info
        print_status "BTRFS filesystem information:"
        btrfs filesystem show "$MOUNT_POINT" || true
        df -h "$MOUNT_POINT"
    else
        print_error "Failed to mount $IMAGE_PATH to $MOUNT_POINT"
        exit 1
    fi
    
else
    # Create new partition starting after partition 2, filling the rest of the disk
    # Start sector is PART2_END_SECTOR + 1, end is 100% (or DISK_SIZE - 1)
    print_status "Creating new partition after partition 2..."
    START_SECTOR=$((PART2_END_SECTOR + 1))
    
    # Use parted to create the partition
    # We'll use the next available partition number (should be 3)
    parted -s "$DEVICE" mkpart primary btrfs "${START_SECTOR}s" 100%
    
    # Wait a moment for the kernel to recognize the new partition
    sleep 2
    
    # Refresh partition table
    partprobe "$DEVICE" 2>/dev/null || true
    sleep 1
    
    # Determine the new partition number (should be 3)
    NEW_PART="${DEVICE}p3"
    
    if [[ ! -b "$NEW_PART" ]]; then
        print_error "New partition $NEW_PART was not created successfully"
        exit 1
    fi
    
    print_status "New partition created: $NEW_PART"
    
    # Format the new partition as BTRFS
    print_status "Formatting $NEW_PART as BTRFS..."
    mkfs.btrfs -f "$NEW_PART"
    
    # Create mount point if it doesn't exist
    if [[ ! -d "$MOUNT_POINT" ]]; then
        print_status "Creating mount point $MOUNT_POINT..."
        mkdir -p "$MOUNT_POINT"
    fi
    
    # Get the UUID of the new partition
    UUID=$(blkid -s UUID -o value "$NEW_PART")
    
    if [[ -z "$UUID" ]]; then
        print_error "Could not determine UUID of new partition"
        exit 1
    fi
    
    print_status "Partition UUID: $UUID"
    
    # Check if entry already exists in fstab
    if grep -q "$MOUNT_POINT" /etc/fstab; then
        print_warning "Entry for $MOUNT_POINT already exists in /etc/fstab"
        print_status "Backing up /etc/fstab to /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
        cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Remove old entry
        sed -i "\|$MOUNT_POINT|d" /etc/fstab
        print_status "Removed old entry from /etc/fstab"
    fi
    
    # Add entry to fstab
    FSTAB_ENTRY="UUID=$UUID $MOUNT_POINT btrfs noatime,compress=zstd:1 0 0"
    print_status "Adding entry to /etc/fstab:"
    echo "  $FSTAB_ENTRY"
    echo "$FSTAB_ENTRY" >> /etc/fstab
    
    # Mount the new partition
    print_status "Mounting $NEW_PART to $MOUNT_POINT..."
    mount "$MOUNT_POINT"
    
    # Verify mount
    if mountpoint -q "$MOUNT_POINT"; then
        print_status "Successfully mounted $NEW_PART to $MOUNT_POINT"
        
        # Show filesystem info
        print_status "BTRFS filesystem information:"
        btrfs filesystem show "$MOUNT_POINT" || true
        df -h "$MOUNT_POINT"
    else
        print_error "Failed to mount $NEW_PART to $MOUNT_POINT"
        exit 1
    fi
fi

print_status "Setup completed successfully!"
if [[ "$USE_IMAGE_FILE" == true ]]; then
    print_status "BTRFS image file is now available at $MOUNT_POINT"
    print_status "Image file location: $IMAGE_PATH"
else
    print_status "BTRFS partition is now available at $MOUNT_POINT"
fi
print_status "The filesystem will automatically mount on boot via /etc/fstab"


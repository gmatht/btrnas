#!/bin/bash
# Script to move /home to a BTRFS subvolume @home on /btrfs
# This allows for better snapshot management of user data

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

# Check if /btrfs exists and is a BTRFS filesystem
if [[ ! -d "/btrfs" ]]; then
    print_error "/btrfs directory does not exist"
    print_error "Please create and mount a BTRFS partition first"
    exit 1
fi

# Check if /btrfs is actually a BTRFS filesystem
if ! btrfs filesystem show /btrfs &>/dev/null; then
    print_error "/btrfs is not a BTRFS filesystem"
    exit 1
fi

# Check if @home subvolume already exists
if btrfs subvolume list /btrfs | grep -q " @home$"; then
    print_warning "Subvolume @home already exists on /btrfs"
    read -p "Do you want to continue? This will use the existing subvolume. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Operation cancelled"
        exit 1
    fi
    USE_EXISTING=true
else
    USE_EXISTING=false
fi

# Check if /home is already a mount point for @home
if mount | grep -q " /home "; then
    MOUNT_INFO=$(mount | grep " /home ")
    if echo "$MOUNT_INFO" | grep -q "subvol=@home\|subvol=/@home"; then
        print_warning "/home is already mounted as @home subvolume"
        print_status "Nothing to do - home is already on BTRFS subvolume"
        exit 0
    else
        print_warning "/home is already a mount point for something else"
        print_warning "Mount info: $MOUNT_INFO"
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Operation cancelled"
            exit 1
        fi
    fi
fi

# Check if users are logged in
LOGGED_IN_USERS=$(who | wc -l)
if [[ $LOGGED_IN_USERS -gt 0 ]]; then
    print_warning "There are users currently logged in:"
    who
    print_warning "It's recommended to run this script when no users are logged in"
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Operation cancelled"
        exit 1
    fi
fi

print_status "Starting migration of /home to /btrfs/@home"
print_warning "This operation will:"
print_warning "  1. Create @home subvolume on /btrfs"
print_warning "  2. Copy all files from /home to /btrfs/@home"
print_warning "  3. Backup original /home to /home.backup"
print_warning "  4. Remove old /home directory"
print_warning "  5. Mount @home subvolume at /home"
print_warning "  6. Update /etc/fstab for automatic mounting"
echo

read -p "Do you want to proceed? (type 'yes' to confirm): " confirmation
if [[ "$confirmation" != "yes" ]]; then
    print_error "Operation cancelled by user"
    exit 1
fi

# Step 1: Create @home subvolume if it doesn't exist
if [[ "$USE_EXISTING" == "false" ]]; then
    print_status "Creating @home subvolume on /btrfs..."
    btrfs subvolume create /btrfs/@home
    print_status "Subvolume @home created"
else
    print_status "Using existing @home subvolume"
fi

# Step 2: Check available space
print_status "Checking available space..."
HOME_SIZE=$(du -sb /home 2>/dev/null | cut -f1)
BTRFS_FREE=$(btrfs filesystem usage /btrfs | grep "Free (estimated)" | awk '{print $3}' | sed 's/[^0-9]//g')
BTRFS_FREE_BYTES=$(btrfs filesystem usage /btrfs | grep "Free (estimated)" | awk '{print $4}')

# Convert to bytes if needed
if [[ "$BTRFS_FREE_BYTES" == *"GiB"* ]]; then
    BTRFS_FREE_BYTES=$(echo "$BTRFS_FREE" | awk '{print int($1 * 1024 * 1024 * 1024)}')
elif [[ "$BTRFS_FREE_BYTES" == *"MiB"* ]]; then
    BTRFS_FREE_BYTES=$(echo "$BTRFS_FREE" | awk '{print int($1 * 1024 * 1024)}')
fi

if [[ -z "$BTRFS_FREE_BYTES" ]] || [[ "$BTRFS_FREE_BYTES" -lt "$HOME_SIZE" ]]; then
    print_error "Not enough free space on /btrfs"
    print_error "Required: $(numfmt --to=iec-i --suffix=B $HOME_SIZE)"
    print_error "Available: $(btrfs filesystem usage /btrfs | grep 'Free (estimated)')"
    exit 1
fi

print_status "Sufficient space available"

# Step 3: Copy files from /home to /btrfs/@home
print_status "Copying files from /home to /btrfs/@home..."
print_warning "This may take a while depending on the size of /home..."

# Use rsync for efficient copying with progress
if command -v rsync &> /dev/null; then
    rsync -aAXv --info=progress2 /home/ /btrfs/@home/
else
    # Fallback to cp if rsync is not available
    cp -a /home/* /btrfs/@home/ 2>&1 | while IFS= read -r line; do
        echo "  $line"
    done
fi

# Verify copy was successful
if [[ $? -ne 0 ]]; then
    print_error "Failed to copy files from /home to /btrfs/@home"
    print_error "Removing incomplete subvolume..."
    btrfs subvolume delete /btrfs/@home 2>/dev/null || true
    exit 1
fi

print_status "Files copied successfully"

# Step 4: Set correct permissions
print_status "Setting correct permissions on /btrfs/@home..."
chown -R root:root /btrfs/@home
# Restore original permissions from /home
if [[ -f /btrfs/@home/.permissions_backup ]]; then
    # If we saved permissions, restore them
    print_status "Restoring original permissions..."
else
    # Set default permissions
    find /btrfs/@home -type d -exec chmod 755 {} \;
    find /btrfs/@home -type f -exec chmod 644 {} \;
fi

# Step 5: Backup original /home
print_status "Creating backup of original /home..."
if [[ -d "/home.backup" ]]; then
    print_warning "/home.backup already exists, removing old backup..."
    rm -rf /home.backup
fi

mv /home /home.backup
print_status "Original /home backed up to /home.backup"

# Step 6: Create new /home mount point
print_status "Creating new /home mount point..."
mkdir -p /home

# Step 7: Mount @home subvolume at /home
print_status "Mounting @home subvolume at /home..."
mount -o subvol=@home /btrfs /home

if ! mountpoint -q /home; then
    print_error "Failed to mount @home subvolume at /home"
    print_error "Restoring original /home..."
    umount /home 2>/dev/null || true
    rmdir /home
    mv /home.backup /home
    exit 1
fi

print_status "Subvolume mounted successfully"

# Step 8: Update /etc/fstab
print_status "Updating /etc/fstab..."

# Get the UUID of /btrfs
BTRFS_UUID=$(blkid -s UUID -o value $(findmnt -n -o SOURCE /btrfs))

if [[ -z "$BTRFS_UUID" ]]; then
    print_error "Could not determine UUID of /btrfs filesystem"
    print_warning "You may need to manually update /etc/fstab"
else
    # Backup fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    
    # Remove old /home entry if it exists
    sed -i '/[[:space:]]\/home[[:space:]]/d' /etc/fstab
    
    # Add new entry for @home subvolume
    FSTAB_ENTRY="UUID=$BTRFS_UUID /home btrfs subvol=@home,noatime,compress=zstd:1 0 0"
    echo "$FSTAB_ENTRY" >> /etc/fstab
    
    print_status "Added to /etc/fstab:"
    echo "  $FSTAB_ENTRY"
fi

# Step 9: Verify everything works
print_status "Verifying setup..."
if [[ -d "/home" ]] && mountpoint -q /home; then
    HOME_MOUNT=$(mount | grep " /home ")
    if echo "$HOME_MOUNT" | grep -q "subvol=@home\|subvol=/@home"; then
        print_status "Verification successful!"
        echo
        print_status "=== Migration Summary ==="
        print_status "Original /home: backed up to /home.backup"
        print_status "New /home: mounted from /btrfs/@home"
        print_status "Subvolume: /btrfs/@home"
        echo
        print_status "You can now:"
        print_status "  1. Test that everything works correctly"
        print_status "  2. Remove /home.backup after verifying (when ready):"
        print_status "     sudo rm -rf /home.backup"
        print_status "  3. Create snapshots of @home for backup:"
        print_status "     sudo btrfs subvolume snapshot /btrfs/@home /btrfs/@home-snapshot-$(date +%Y%m%d)"
        echo
        print_warning "IMPORTANT: Reboot the system to ensure everything works correctly"
    else
        print_error "Verification failed - /home is not mounted as @home subvolume"
        exit 1
    fi
else
    print_error "Verification failed - /home is not properly mounted"
    exit 1
fi

print_status "Migration completed successfully!"



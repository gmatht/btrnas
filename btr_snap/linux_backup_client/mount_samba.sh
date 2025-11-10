#!/bin/bash
# Helper script to mount Samba share
# This is used by the installation script and can be run manually if needed

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Configuration
MOUNT_POINT="/mnt/samba-backup"
CREDENTIALS_FILE="/etc/samba/backup-credentials"

# Check if credentials file exists
if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    print_error "Credentials file not found: $CREDENTIALS_FILE"
    print_error "Please run install_linux_backup.sh first"
    exit 1
fi

# Check if mount point exists, create if not
if [[ ! -d "$MOUNT_POINT" ]]; then
    print_status "Creating mount point: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
fi

# Check if already mounted
if mountpoint -q "$MOUNT_POINT"; then
    print_warning "Samba share is already mounted at $MOUNT_POINT"
    exit 0
fi

# Read server and share from credentials or use parameters
if [[ $# -ge 2 ]]; then
    SERVER="$1"
    SHARE="$2"
else
    # Try to read from systemd mount unit if it exists
    MOUNT_UNIT="/etc/systemd/system/mnt-samba-backup.mount"
    if [[ -f "$MOUNT_UNIT" ]]; then
        SERVER=$(grep -oP 'What=\K[^ ]+' "$MOUNT_UNIT" | cut -d'/' -f3)
        SHARE=$(grep -oP 'What=\K[^ ]+' "$MOUNT_UNIT" | cut -d'/' -f4-)
    else
        print_error "Please provide server and share: $0 <server> <share>"
        exit 1
    fi
fi

# Mount the share
print_status "Mounting Samba share //$SERVER/$SHARE to $MOUNT_POINT"

if mount -t cifs "//$SERVER/$SHARE" "$MOUNT_POINT" -o credentials="$CREDENTIALS_FILE",uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0664,dir_mode=0775; then
    print_status "Samba share mounted successfully"
    
    # Test write access
    TEST_FILE="$MOUNT_POINT/.test_write_$(date +%s)"
    if touch "$TEST_FILE" 2>/dev/null; then
        rm -f "$TEST_FILE"
        print_status "Write access verified"
    else
        print_warning "Could not write to mount point. Check permissions."
    fi
else
    print_error "Failed to mount Samba share"
    exit 1
fi



#!/bin/bash
# Script to set up proper permissions on /btrfs structure
# Ensures users can browse /btrfs but only access their own home directories
# Should be run after /btrfs is set up and after new snapshots are created

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

# Check if /btrfs exists
if [[ ! -d "/btrfs" ]]; then
    print_error "/btrfs directory does not exist"
    exit 1
fi

print_status "Setting up permissions on /btrfs structure..."

# Set permissions on /btrfs root
print_status "Setting permissions on /btrfs root directory..."
chmod 755 /btrfs
chown root:root /btrfs

# Set permissions on @home subvolume
if [[ -d "/btrfs/@home" ]]; then
    print_status "Setting permissions on /btrfs/@home..."
    chmod 755 /btrfs/@home
    chown root:root /btrfs/@home
    
    # Set permissions on user home directories
    print_status "Setting permissions on user home directories..."
    for user_dir in /btrfs/@home/*; do
        if [[ -d "$user_dir" ]]; then
            username=$(basename "$user_dir")
            # Check if user exists
            if id "$username" &>/dev/null; then
                chown -R "$username:$username" "$user_dir"
                chmod 700 "$user_dir"
                print_status "  Set permissions for $username"
            else
                print_warning "  User $username does not exist, skipping..."
            fi
        fi
    done
else
    print_warning "/btrfs/@home does not exist, skipping..."
fi

# Set permissions on snapshot directory
if [[ -d "/btrfs/snapshot" ]]; then
    print_status "Setting permissions on /btrfs/snapshot directory..."
    chmod 755 /btrfs/snapshot
    chown root:root /btrfs/snapshot
    
    # Set permissions on each snapshot
    print_status "Setting permissions on snapshots..."
    snapshot_count=0
    for snapshot in /btrfs/snapshot/*; do
        if [[ -d "$snapshot" ]]; then
            snapshot_name=$(basename "$snapshot")
            # Set snapshot directory permissions (users can list)
            chmod 755 "$snapshot"
            chown root:root "$snapshot"
            
            # Set permissions on user home subdirectories within snapshots
            if [[ -d "$snapshot/@home" ]]; then
                for user_dir in "$snapshot/@home"/*; do
                    if [[ -d "$user_dir" ]]; then
                        username=$(basename "$user_dir")
                        # Check if user exists
                        if id "$username" &>/dev/null; then
                            chown -R "$username:$username" "$user_dir"
                            chmod 700 "$user_dir"
                        fi
                    fi
                done
            fi
            
            snapshot_count=$((snapshot_count + 1))
        fi
    done
    
    if [[ $snapshot_count -gt 0 ]]; then
        print_status "  Processed $snapshot_count snapshot(s)"
    else
        print_warning "  No snapshots found"
    fi
else
    print_warning "/btrfs/snapshot does not exist, skipping..."
fi

print_status "Permission setup completed!"



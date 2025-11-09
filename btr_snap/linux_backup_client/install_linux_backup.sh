#!/bin/bash
# Installation script for Linux backup client using lsyncd
# This script sets up continuous backup to Samba share

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_section "Linux Backup Client Installation (lsyncd)"

# Step 1: Detect package manager and install lsyncd
print_section "Step 1: Installing lsyncd"

if command -v apt-get &> /dev/null; then
    print_status "Detected apt package manager (Debian/Ubuntu)"
    apt-get update
    apt-get install -y lsyncd cifs-utils rsync
elif command -v yum &> /dev/null; then
    print_status "Detected yum package manager (RHEL/CentOS)"
    yum install -y lsyncd cifs-utils rsync
elif command -v dnf &> /dev/null; then
    print_status "Detected dnf package manager (Fedora)"
    dnf install -y lsyncd cifs-utils rsync
elif command -v pacman &> /dev/null; then
    print_status "Detected pacman package manager (Arch)"
    pacman -S --noconfirm lsyncd cifs-utils rsync
elif command -v zypper &> /dev/null; then
    print_status "Detected zypper package manager (openSUSE)"
    zypper install -y lsyncd cifs-utils rsync
else
    print_error "Could not detect package manager. Please install lsyncd, cifs-utils, and rsync manually."
    exit 1
fi

print_status "lsyncd and dependencies installed successfully"
echo ""

# Step 2: Get configuration from user
print_section "Step 2: Configuration"

# Samba server and share
echo "Enter Samba server details:"
read -p "Samba server hostname or IP: " SAMBA_SERVER
if [[ -z "$SAMBA_SERVER" ]]; then
    print_error "Samba server is required"
    exit 1
fi

read -p "Samba share name (e.g., btrfs or backups): " SAMBA_SHARE
if [[ -z "$SAMBA_SHARE" ]]; then
    print_error "Samba share name is required"
    exit 1
fi

# Source directory
echo ""
read -p "Source directory to backup (default: /home): " SOURCE_DIR
if [[ -z "$SOURCE_DIR" ]]; then
    SOURCE_DIR="/home"
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    print_error "Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

# Credentials
echo ""
echo "Enter Samba credentials:"
read -p "Samba username: " SAMBA_USERNAME
if [[ -z "$SAMBA_USERNAME" ]]; then
    print_error "Samba username is required"
    exit 1
fi

read -sp "Samba password: " SAMBA_PASSWORD
echo ""
if [[ -z "$SAMBA_PASSWORD" ]]; then
    print_error "Samba password is required"
    exit 1
fi

# Mount point
MOUNT_POINT="/mnt/samba-backup"
CREDENTIALS_FILE="/etc/samba/backup-credentials"

print_status "Configuration summary:"
echo "  Server: $SAMBA_SERVER"
echo "  Share: $SAMBA_SHARE"
echo "  Source: $SOURCE_DIR"
echo "  Mount point: $MOUNT_POINT"
echo ""

# Step 3: Create credentials file
print_section "Step 3: Setting up credentials"

if [[ -f "$CREDENTIALS_FILE" ]]; then
    print_warning "Credentials file already exists. Backing up..."
    cp "$CREDENTIALS_FILE" "${CREDENTIALS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
fi

cat > "$CREDENTIALS_FILE" << EOF
username=$SAMBA_USERNAME
password=$SAMBA_PASSWORD
domain=WORKGROUP
EOF

chmod 600 "$CREDENTIALS_FILE"
print_status "Credentials file created: $CREDENTIALS_FILE"
echo ""

# Step 4: Create mount point and test mount
print_section "Step 4: Setting up Samba mount"

if [[ ! -d "$MOUNT_POINT" ]]; then
    mkdir -p "$MOUNT_POINT"
    print_status "Created mount point: $MOUNT_POINT"
fi

# Test mount
print_status "Testing Samba connection..."
if mount -t cifs "//$SAMBA_SERVER/$SAMBA_SHARE" "$MOUNT_POINT" -o credentials="$CREDENTIALS_FILE",uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0664,dir_mode=0775; then
    print_status "Samba mount test successful"
    
    # Test write
    TEST_FILE="$MOUNT_POINT/.test_write_$(date +%s)"
    if touch "$TEST_FILE" 2>/dev/null; then
        rm -f "$TEST_FILE"
        print_status "Write access verified"
    else
        print_warning "Could not write to mount point. Check permissions."
    fi
    
    # Unmount test
    umount "$MOUNT_POINT"
    print_status "Test mount unmounted"
else
    print_error "Failed to mount Samba share. Please check:"
    echo "  - Server is accessible: ping $SAMBA_SERVER"
    echo "  - Share name is correct: $SAMBA_SHARE"
    echo "  - Credentials are correct"
    exit 1
fi

echo ""

# Step 5: Create systemd mount unit
print_section "Step 5: Creating systemd mount unit"

MOUNT_UNIT="/etc/systemd/system/mnt-samba-backup.mount"
MOUNT_UNIT_NAME="mnt-samba-backup.mount"

cat > "$MOUNT_UNIT" << EOF
[Unit]
Description=Mount Samba Share for Backup
Before=lsyncd-backup.service
Requires=network-online.target
After=network-online.target

[Mount]
What=//$SAMBA_SERVER/$SAMBA_SHARE
Where=$MOUNT_POINT
Type=cifs
Options=credentials=$CREDENTIALS_FILE,uid=$(id -u),gid=$(id -g),iocharset=utf8,file_mode=0664,dir_mode=0775,_netdev

[Install]
WantedBy=multi-user.target
EOF

print_status "Systemd mount unit created: $MOUNT_UNIT"
echo ""

# Step 6: Create lsyncd configuration
print_section "Step 6: Creating lsyncd configuration"

LSYNCD_CONF="/etc/lsyncd/lsyncd.conf.lua"
LSYNCD_LOG_DIR="/var/log/lsyncd"

# Create log directory
if [[ ! -d "$LSYNCD_LOG_DIR" ]]; then
    mkdir -p "$LSYNCD_LOG_DIR"
    print_status "Created log directory: $LSYNCD_LOG_DIR"
fi

# Backup existing config if it exists
if [[ -f "$LSYNCD_CONF" ]]; then
    print_warning "lsyncd configuration already exists. Backing up..."
    cp "$LSYNCD_CONF" "${LSYNCD_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Create configuration from template
if [[ -f "$SCRIPT_DIR/lsyncd.conf" ]]; then
    cp "$SCRIPT_DIR/lsyncd.conf" "$LSYNCD_CONF"
    # Replace source and target in config
    sed -i "s|source = \"/home\"|source = \"$SOURCE_DIR\"|g" "$LSYNCD_CONF"
    sed -i "s|target = \"/mnt/samba-backup\"|target = \"$MOUNT_POINT\"|g" "$LSYNCD_CONF"
    print_status "lsyncd configuration created from template"
else
    # Create basic configuration
    cat > "$LSYNCD_CONF" << EOF
-- lsyncd configuration for backing up to Samba share

settings {
    logfile = "$LSYNCD_LOG_DIR/lsyncd.log",
    statusFile = "$LSYNCD_LOG_DIR/lsyncd.status",
    statusInterval = 20,
    nodaemon = false,
    inotifyMode = "CloseWrite",
    maxProcesses = 1,
    maxDelays = 1,
}

sync {
    default.rsync,
    source = "$SOURCE_DIR",
    target = "$MOUNT_POINT",
    exclude = {
        ".*/.*cache.*",
        ".*/.*Cache.*",
        ".*/.*tmp.*",
        ".*/.*Tmp.*",
        ".*/.*temp.*",
        ".*/.*Temp.*",
        ".*/.cache/",
        ".*/.tmp/",
        ".*/.temp/",
        ".*/.mozilla/.*cache.*",
        ".*/.mozilla/firefox/.*/cache.*",
        ".*/.chromium/.*/Cache.*",
        ".*/.google-chrome/.*/Cache.*",
        ".*/.Trash/",
        ".*/.local/share/Trash/",
        ".*/.thumbnails/",
        ".*/.recently-used",
        ".*/.Xauthority",
        ".*/.ICEauthority",
        ".*/.npm/",
        ".*/.pip/",
        ".*/.cargo/registry/",
    },
    rsync = {
        archive = true,
        compress = false,
        verbose = false,
        _extra = {
            "--delete",
            "--delete-excluded",
        },
    },
    delay = 5,
}
EOF
    print_status "lsyncd configuration created"
fi

echo ""

# Step 7: Install systemd service
print_section "Step 7: Installing systemd service"

if [[ -f "$SCRIPT_DIR/lsyncd-backup.service" ]]; then
    cp "$SCRIPT_DIR/lsyncd-backup.service" /etc/systemd/system/
    print_status "Systemd service file installed"
else
    print_error "Service file not found: $SCRIPT_DIR/lsyncd-backup.service"
    exit 1
fi

# Reload systemd
systemctl daemon-reload
print_status "Systemd daemon reloaded"
echo ""

# Step 8: Enable and start services
print_section "Step 8: Starting services"

# Enable and start mount
systemctl enable "$MOUNT_UNIT_NAME"
systemctl start "$MOUNT_UNIT_NAME"

if systemctl is-active --quiet "$MOUNT_UNIT_NAME"; then
    print_status "Samba mount is active"
else
    print_error "Failed to start Samba mount. Check logs: journalctl -u $MOUNT_UNIT_NAME"
    exit 1
fi

# Wait a moment for mount to be ready
sleep 2

# Enable and start lsyncd
systemctl enable lsyncd-backup.service
systemctl start lsyncd-backup.service

if systemctl is-active --quiet lsyncd-backup.service; then
    print_status "lsyncd service is active"
else
    print_error "Failed to start lsyncd. Check logs: journalctl -u lsyncd-backup"
    exit 1
fi

echo ""

# Step 9: Summary
print_section "Installation Complete!"

print_status "Configuration Summary:"
echo "  ✓ lsyncd installed and configured"
echo "  ✓ Samba share mounted at: $MOUNT_POINT"
echo "  ✓ Source directory: $SOURCE_DIR"
echo "  ✓ Services enabled to start on boot"
echo ""

print_status "Useful Commands:"
echo "  Check lsyncd status:"
echo "    systemctl status lsyncd-backup"
echo ""
echo "  Check mount status:"
echo "    systemctl status mnt-samba-backup.mount"
echo ""
echo "  View lsyncd logs:"
echo "    tail -f $LSYNCD_LOG_DIR/lsyncd.log"
echo ""
echo "  View service logs:"
echo "    journalctl -u lsyncd-backup -f"
echo ""
echo "  Manually mount/unmount:"
echo "    systemctl start mnt-samba-backup.mount"
echo "    systemctl stop mnt-samba-backup.mount"
echo ""
echo "  Restart services:"
echo "    systemctl restart lsyncd-backup"
echo ""

print_warning "Note: The backup will start automatically on system boot."
print_warning "Make sure the Samba server is accessible on the network."


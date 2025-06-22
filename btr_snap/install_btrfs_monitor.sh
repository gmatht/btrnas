#!/bin/bash
# BTRFS Snapshot Monitor Installation Script

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

# Check if BTRFS tools are installed
if ! command -v btrfs &> /dev/null; then
    print_warning "BTRFS tools not found. Attempting to install..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y btrfs-progs
    elif command -v yum &> /dev/null; then
        yum install -y btrfs-progs
    elif command -v dnf &> /dev/null; then
        dnf install -y btrfs-progs
    elif command -v pacman &> /dev/null; then
        pacman -S btrfs-progs
    else
        print_error "Could not install BTRFS tools automatically. Please install btrfs-progs manually."
        exit 1
    fi
fi

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    print_error "Python 3 is required but not installed."
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define installation paths
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc"
SERVICE_DIR="/etc/systemd/system"

print_status "Installing BTRFS Snapshot Monitor..."

# Copy the main script
print_status "Copying main script to $INSTALL_DIR..."
cp "$SCRIPT_DIR/btrfs_snapshot_monitor.py" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/btrfs_snapshot_monitor.py"

# Copy configuration file
print_status "Copying configuration file to $CONFIG_DIR..."
cp "$SCRIPT_DIR/btrfs_snapshot_monitor.conf" "$CONFIG_DIR/"

# Copy systemd service file
print_status "Copying systemd service file to $SERVICE_DIR..."
cp "$SCRIPT_DIR/btrfs-snapshot-monitor.service" "$SERVICE_DIR/"

# Update the service file with the correct path
sed -i "s|/path/to/btrfs_snapshot_monitor.py|$INSTALL_DIR/btrfs_snapshot_monitor.py|g" "$SERVICE_DIR/btrfs-snapshot-monitor.service"

# Create log directory
print_status "Creating log directory..."
mkdir -p /var/log

# Set proper permissions
print_status "Setting permissions..."
chmod 644 "$CONFIG_DIR/btrfs_snapshot_monitor.conf"
chmod 644 "$SERVICE_DIR/btrfs-snapshot-monitor.service"

# Reload systemd
print_status "Reloading systemd daemon..."
systemctl daemon-reload

# Test the script
print_status "Testing the script..."
if python3 "$INSTALL_DIR/btrfs_snapshot_monitor.py" --help &> /dev/null; then
    print_status "Script test successful!"
else
    print_warning "Script test failed, but continuing installation..."
fi

print_status "Installation completed successfully!"
echo
print_status "Next steps:"
echo "1. Edit the configuration file: sudo nano $CONFIG_DIR/btrfs_snapshot_monitor.conf"
echo "2. Enable and start the service:"
echo "   sudo systemctl enable btrfs-snapshot-monitor.service"
echo "   sudo systemctl start btrfs-snapshot-monitor.service"
echo "3. Check service status: sudo systemctl status btrfs-snapshot-monitor.service"
echo "4. View logs: sudo journalctl -u btrfs-snapshot-monitor.service -f"
echo
print_status "For manual testing, run:"
echo "sudo python3 $INSTALL_DIR/btrfs_snapshot_monitor.py --dry-run" 
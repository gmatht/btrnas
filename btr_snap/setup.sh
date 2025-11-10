#!/bin/bash
# Complete setup script for BTRFS snapshot system
# This script sets up the BTRFS partition, installs the snapshot monitor, and installs samba and vsftpd

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

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to detect package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# Function to install packages
install_packages() {
    local packages=("$@")
    local pkg_manager=$(detect_package_manager)
    
    print_status "Installing packages: ${packages[*]}"
    
    case $pkg_manager in
        apt)
            apt-get update
            apt-get install -y "${packages[@]}"
            ;;
        yum)
            yum install -y "${packages[@]}"
            ;;
        dnf)
            dnf install -y "${packages[@]}"
            ;;
        pacman)
            pacman -S --noconfirm "${packages[@]}"
            ;;
        *)
            print_error "Unknown package manager. Please install the following packages manually: ${packages[*]}"
            return 1
            ;;
    esac
}

# Main setup process
print_section "BTRFS Snapshot System Setup"

# Step 1: Setup BTRFS partition
print_section "Step 1: Setting up BTRFS partition"
if [[ -f "$SCRIPT_DIR/setup_btrfs_partition.sh" ]]; then
    print_status "Running setup_btrfs_partition.sh..."
    bash "$SCRIPT_DIR/setup_btrfs_partition.sh"
    print_status "BTRFS partition setup completed"
else
    print_error "setup_btrfs_partition.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Step 2: Install snapshot monitor
print_section "Step 2: Installing BTRFS Snapshot Monitor"
if [[ -f "$SCRIPT_DIR/install_btrfs_monitor.sh" ]]; then
    print_status "Running install_btrfs_monitor.sh..."
    bash "$SCRIPT_DIR/install_btrfs_monitor.sh"
    print_status "Snapshot monitor installation completed"
    
    # Enable and start the service
    print_status "Enabling and starting btrfs-snapshot-monitor service..."
    systemctl daemon-reload
    systemctl enable btrfs-snapshot-monitor.service
    systemctl start btrfs-snapshot-monitor.service
    print_status "Snapshot monitor service started"
else
    print_error "install_btrfs_monitor.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Step 3: Install Samba
print_section "Step 3: Installing Samba"
if ! command -v smbd &> /dev/null; then
    install_packages "samba"
    print_status "Samba installed successfully"
    
    # Enable Samba service
    print_status "Enabling Samba service..."
    systemctl enable smbd
    systemctl enable nmbd
    print_status "Samba services enabled (not started - configure before starting)"
else
    print_status "Samba is already installed"
fi

# Step 4: Install vsftpd
print_section "Step 4: Installing vsftpd"
if ! command -v vsftpd &> /dev/null; then
    install_packages "vsftpd"
    print_status "vsftpd installed successfully"
    
    # Enable vsftpd service
    print_status "Enabling vsftpd service..."
    systemctl enable vsftpd
    print_status "vsftpd service enabled (not started - configure before starting)"
else
    print_status "vsftpd is already installed"
fi

# Final summary
print_section "Setup Complete!"
print_status "All components have been installed and configured."
echo
print_status "Summary:"
echo "  ✓ BTRFS partition setup completed"
echo "  ✓ BTRFS Snapshot Monitor installed and running"
echo "  ✓ Samba installed (configure /etc/samba/smb.conf before starting)"
echo "  ✓ vsftpd installed (configure /etc/vsftpd.conf before starting)"
echo
print_status "Next steps:"
echo "1. Configure Samba: sudo nano /etc/samba/smb.conf"
echo "   Then start: sudo systemctl start smbd nmbd"
echo
echo "2. Configure vsftpd: sudo nano /etc/vsftpd.conf"
echo "   Then start: sudo systemctl start vsftpd"
echo
echo "3. Check snapshot monitor status:"
echo "   sudo systemctl status btrfs-snapshot-monitor.service"
echo
echo "4. View snapshot monitor logs:"
echo "   sudo journalctl -u btrfs-snapshot-monitor.service -f"
echo




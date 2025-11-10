#!/bin/bash
# Script to install and configure vsftpd and Samba for BTRFS snapshot access
# This script automates the setup process

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "BTRFS vsftpd and Samba Setup"
echo "========================================"
echo

# Step 1: Install packages
print_status "Step 1: Installing required packages..."
if command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y vsftpd samba samba-common-bin
elif command -v yum &> /dev/null; then
    yum install -y vsftpd samba samba-common
elif command -v dnf &> /dev/null; then
    dnf install -y vsftpd samba samba-common
elif command -v pacman &> /dev/null; then
    pacman -S --noconfirm vsftpd samba
else
    print_error "Could not detect package manager. Please install vsftpd and samba manually."
    exit 1
fi

print_status "Packages installed successfully"
echo

# Step 2: Backup existing configurations
print_status "Step 2: Backing up existing configurations..."
if [[ -f "/etc/vsftpd.conf" ]]; then
    cp /etc/vsftpd.conf /etc/vsftpd.conf.backup.$(date +%Y%m%d_%H%M%S)
    print_status "Backed up /etc/vsftpd.conf"
fi

if [[ -f "/etc/samba/smb.conf" ]]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.backup.$(date +%Y%m%d_%H%M%S)
    print_status "Backed up /etc/samba/smb.conf"
fi
echo

# Step 3: Configure vsftpd
print_status "Step 3: Configuring vsftpd..."
if [[ -f "$SCRIPT_DIR/vsftpd.conf.example" ]]; then
    cp "$SCRIPT_DIR/vsftpd.conf.example" /etc/vsftpd.conf
    print_status "Created /etc/vsftpd.conf from example"
else
    print_error "vsftpd.conf.example not found in $SCRIPT_DIR"
    print_error "Please create /etc/vsftpd.conf manually"
fi
echo

# Step 4: Configure Samba
print_status "Step 4: Configuring Samba..."
if [[ -f "$SCRIPT_DIR/smb.conf.example" ]]; then
    # Check if smb.conf exists and has [global] section
    if [[ -f "/etc/samba/smb.conf" ]] && grep -q "^\[global\]" /etc/samba/smb.conf; then
        # Append our shares to existing config
        print_status "Appending BTRFS shares to existing /etc/samba/smb.conf"
        echo "" >> /etc/samba/smb.conf
        echo "# BTRFS shares - added by install script" >> /etc/samba/smb.conf
        grep -v "^#" "$SCRIPT_DIR/smb.conf.example" | grep -v "^$" | grep -v "^\[global\]" >> /etc/samba/smb.conf
    else
        # Create new config
        cp "$SCRIPT_DIR/smb.conf.example" /etc/samba/smb.conf
        print_status "Created /etc/samba/smb.conf from example"
    fi
else
    print_error "smb.conf.example not found in $SCRIPT_DIR"
    print_error "Please configure /etc/samba/smb.conf manually"
fi
echo

# Step 5: Set up permissions
print_status "Step 5: Setting up permissions..."
if [[ -f "$SCRIPT_DIR/setup_btrfs_permissions.sh" ]]; then
    chmod +x "$SCRIPT_DIR/setup_btrfs_permissions.sh"
    "$SCRIPT_DIR/setup_btrfs_permissions.sh"
else
    print_warning "setup_btrfs_permissions.sh not found, skipping permission setup"
fi
echo

# Step 6: Configure firewall (if applicable)
print_status "Step 6: Configuring firewall..."
if command -v ufw &> /dev/null; then
    print_status "Opening FTP and SMB ports with ufw..."
    ufw allow 21/tcp comment 'FTP'
    ufw allow 21100:21110/tcp comment 'FTP Passive'
    ufw allow 445/tcp comment 'SMB'
    ufw allow 139/tcp comment 'SMB NetBIOS'
    print_status "Firewall rules added"
elif command -v firewall-cmd &> /dev/null; then
    print_status "Opening FTP and SMB ports with firewalld..."
    firewall-cmd --permanent --add-service=ftp
    firewall-cmd --permanent --add-port=21100-21110/tcp
    firewall-cmd --permanent --add-service=samba
    firewall-cmd --reload
    print_status "Firewall rules added"
else
    print_warning "No firewall detected or firewall not configured. Please open ports manually:"
    print_warning "  - FTP: 21/tcp"
    print_warning "  - FTP Passive: 21100-21110/tcp"
    print_warning "  - SMB: 445/tcp, 139/tcp"
fi
echo

# Step 7: Start and enable services
print_status "Step 7: Starting and enabling services..."

# Test vsftpd configuration
if vsftpd -olisten=NO /etc/vsftpd.conf &>/dev/null; then
    print_status "vsftpd configuration is valid"
    pkill vsftpd || true
else
    print_error "vsftpd configuration has errors. Please check /etc/vsftpd.conf"
fi

# Test Samba configuration
if testparm -s &>/dev/null; then
    print_status "Samba configuration is valid"
else
    print_warning "Samba configuration may have issues. Run 'testparm' to check"
fi

# Start services
systemctl enable vsftpd
systemctl start vsftpd
print_status "vsftpd service started and enabled"

systemctl enable smbd
systemctl enable nmbd
systemctl start smbd
systemctl start nmbd
print_status "Samba services started and enabled"
echo

# Step 8: Summary
print_status "Setup completed!"
echo
print_status "Next steps:"
print_status "  1. Verify /btrfs directory exists and is accessible"
print_status "  2. Run setup_btrfs_permissions.sh to set proper permissions"
print_status "  3. Test FTP access: ftp localhost (navigate to /@home/username/ and /snapshot/)"
print_status "  4. Test SMB access: smbclient //localhost/btrfs -U username"
print_status "  5. Review configuration files:"
print_status "     - /etc/vsftpd.conf"
print_status "     - /etc/samba/smb.conf"
echo
print_warning "IMPORTANT: Review and adjust the configuration files as needed for your environment!"



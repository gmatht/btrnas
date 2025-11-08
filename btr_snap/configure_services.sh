#!/bin/bash
# Configure Samba and vsftpd for read-write access to home directories

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

# Home directory path (from BTRFS setup)
HOME_DIR="/btrfs/home"

print_section "Configuring Samba and vsftpd for Home Directory Access"

# Step 1: Configure Samba
print_section "Step 1: Configuring Samba"

SAMBA_CONF="/etc/samba/smb.conf"

# Backup existing config if it exists
if [[ -f "$SAMBA_CONF" ]]; then
    print_status "Backing up existing Samba configuration..."
    cp "$SAMBA_CONF" "${SAMBA_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Check if home directory share already exists
if [[ -f "$SAMBA_CONF" ]] && grep -q "\[homes\]" "$SAMBA_CONF"; then
    print_warning "Samba [homes] share already exists. Updating configuration..."
    # Remove existing [homes] section
    sed -i '/^\[homes\]/,/^\[/ { /^\[homes\]/! { /^\[/!d; }; }' "$SAMBA_CONF"
    # Remove the [homes] line itself if it's still there
    sed -i '/^\[homes\]$/d' "$SAMBA_CONF"
fi

# Add or update [homes] section
print_status "Adding [homes] share configuration to Samba..."
cat >> "$SAMBA_CONF" << 'EOF'

# Home directories share - allows users to access their home directories
[homes]
   comment = Home Directories
   path = /btrfs/home/%S
   browseable = no
   read only = no
   create mask = 0664
   directory mask = 0775
   valid users = %S
   force user = %S
   force group = %S
EOF

print_status "Samba configuration updated"

# Step 2: Configure vsftpd
print_section "Step 2: Configuring vsftpd"

VSFTPD_CONF="/etc/vsftpd.conf"

# Backup existing config if it exists
if [[ -f "$VSFTPD_CONF" ]]; then
    print_status "Backing up existing vsftpd configuration..."
    cp "$VSFTPD_CONF" "${VSFTPD_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Create or update vsftpd configuration
print_status "Configuring vsftpd for home directory access..."

# Check if configuration already has these settings and update them
if [[ -f "$VSFTPD_CONF" ]]; then
    # Comment out conflicting settings if they exist
    sed -i 's/^\(# *\)*\(local_enable\)=.*/# \2=YES/' "$VSFTPD_CONF"
    sed -i 's/^\(# *\)*\(write_enable\)=.*/# \2=YES/' "$VSFTPD_CONF"
    sed -i 's/^\(# *\)*\(local_umask\)=.*/# \2=022/' "$VSFTPD_CONF"
    sed -i 's/^\(# *\)*\(chroot_local_user\)=.*/# \2=YES/' "$VSFTPD_CONF"
    sed -i 's/^\(# *\)*\(allow_writeable_chroot\)=.*/# \2=YES/' "$VSFTPD_CONF"
fi

# Add configuration settings
cat >> "$VSFTPD_CONF" << 'EOF'

# Allow local users to login
local_enable=YES

# Allow write access
write_enable=YES

# Set default file permissions (rw-rw-r--)
local_umask=022

# Chroot users to their home directories
chroot_local_user=YES

# Allow write access in chroot (required for chroot_local_user=YES)
allow_writeable_chroot=YES

# Security settings
hide_ids=YES

# Additional settings for better compatibility
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000
EOF

print_status "vsftpd configuration updated"

# Step 3: Ensure home directory structure exists
print_section "Step 3: Setting up home directory structure"

if [[ ! -d "$HOME_DIR" ]]; then
    print_status "Creating $HOME_DIR directory..."
    mkdir -p "$HOME_DIR"
    chmod 755 "$HOME_DIR"
fi

print_status "Home directory structure verified"

# Step 4: Restart services
print_section "Step 4: Restarting services"

# Restart Samba
print_status "Restarting Samba services..."
systemctl restart smbd
systemctl restart nmbd
print_status "Samba services restarted"

# Check Samba status
if systemctl is-active --quiet smbd; then
    print_status "Samba (smbd) is running"
else
    print_error "Samba (smbd) failed to start. Check logs: journalctl -u smbd"
fi

if systemctl is-active --quiet nmbd; then
    print_status "Samba (nmbd) is running"
else
    print_warning "Samba (nmbd) may not be needed on all systems"
fi

# Restart vsftpd
print_status "Restarting vsftpd service..."
systemctl restart vsftpd
print_status "vsftpd service restarted"

# Check vsftpd status
if systemctl is-active --quiet vsftpd; then
    print_status "vsftpd is running"
else
    print_error "vsftpd failed to start. Check logs: journalctl -u vsftpd"
fi

# Final summary
print_section "Configuration Complete!"
print_status "Samba and vsftpd have been configured for home directory access."
echo
print_status "Configuration Summary:"
echo "  ✓ Samba configured to share home directories at /btrfs/home/<username>"
echo "  ✓ Samba services (smbd, nmbd) restarted"
echo "  ✓ vsftpd configured for home directory access"
echo "  ✓ vsftpd service restarted"
echo
print_status "Important Notes:"
echo "1. Users can access their home directories via Samba using:"
echo "   smb://<server-ip>/<username>"
echo
echo "2. Users can access their home directories via FTP using:"
echo "   ftp://<server-ip>"
echo
echo "3. Make sure user accounts exist and have home directories in /btrfs/home/"
echo "   Example: mkdir -p /btrfs/home/username && chown username:username /btrfs/home/username"
echo
echo "4. For Samba, you may need to set user passwords:"
echo "   sudo smbpasswd -a username"
echo
echo "5. Check service status:"
echo "   sudo systemctl status smbd"
echo "   sudo systemctl status vsftpd"
echo


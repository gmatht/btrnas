#!/bin/bash

# Gmail Download Service Setup Script
# This script sets up offlineimap to download Gmail to maildir

echo "Setting up Gmail download service for gmatht@gmail.com..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root. Please run as the user gmatht."
   exit 1
fi

# Check if offlineimap is installed
if ! command -v offlineimap &> /dev/null; then
    echo "Error: offlineimap is not installed. Please install it first."
    echo "On Ubuntu/Debian: sudo apt-get install offlineimap"
    echo "On CentOS/RHEL: sudo yum install offlineimap"
    echo "On Arch: sudo pacman -S offlineimap"
    exit 1
fi

# Create mail directory
echo "Creating mail directory..."
mkdir -p ~/Mail/gmatht

# Prompt for Gmail password
echo "Please enter your Gmail password (or app password if 2FA is enabled):"
read -s GMAIL_PASSWORD
if [[ $GMAIL_PASSWORD == *" "* ]]; then
    echo "Warning: Your Gmail password contains spaces. It is necessary to remove spaces from Gmail app passwords."
    echo "Do you want to remove spaces from your password? (yes/no)"
    read -r answer
    if [[ $answer == "yes" ]]; then
        GMAIL_PASSWORD=${GMAIL_PASSWORD// /}
        echo "Spaces have been removed from your password."
    else
        echo "Please remove spaces from your password manually."
    fi
fi

# Create password file
echo "Creating password file..."
cat > ~/.offlineimap.py << EOF
# Offlineimap password configuration
gmatht_password = "$GMAIL_PASSWORD"
EOF

chmod 600 ~/.offlineimap.py

# Copy service files to systemd directory
echo "Installing systemd service files..."
sudo cp gmail-download.service /etc/systemd/system/
sudo cp gmail-download.timer /etc/systemd/system/

# Reload systemd daemon
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

# Enable and start the timer
echo "Enabling and starting Gmail download timer..."
sudo systemctl enable gmail-download.timer
sudo systemctl start gmail-download.timer

# Test the service
echo "Testing Gmail download service..."
sudo systemctl start gmail-download.service

# Check service status
echo "Checking service status..."
sudo systemctl status gmail-download.service --no-pager

echo ""
echo "Setup complete!"
echo ""
echo "Useful commands:"
echo "  Check timer status:  sudo systemctl status gmail-download.timer"
echo "  Check service status: sudo systemctl status gmail-download.service"
echo "  Manual sync:         sudo systemctl start gmail-download.service"
echo "  View logs:           sudo journalctl -u gmail-download.service -f"
echo "  Disable timer:       sudo systemctl disable gmail-download.timer"
echo ""
echo "Mail will be downloaded to: ~/Mail/gmatht"
echo "Sync frequency: Every 15 minutes" 
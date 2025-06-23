#!/bin/bash

# Autossh Daemon Installation Script
# This script installs and enables the autossh systemd service

SERVICE_FILE="autossh.service"
SERVICE_NAME="autossh"

echo "Installing autossh systemd daemon..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

# Check if autossh is installed
if ! command -v autossh &> /dev/null; then
    echo "Error: autossh is not installed. Please install it first."
    echo "On Ubuntu/Debian: sudo apt-get install autossh"
    echo "On CentOS/RHEL: sudo yum install autossh"
    echo "On Arch: sudo pacman -S autossh"
    exit 1
fi

# Copy service file to systemd directory
echo "Copying service file to /etc/systemd/system/"
cp "$SERVICE_FILE" /etc/systemd/system/

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable the service to start on boot
echo "Enabling service to start on boot..."
systemctl enable "$SERVICE_NAME"

# Start the service
echo "Starting autossh service..."
systemctl start "$SERVICE_NAME"

# Check service status
echo "Checking service status..."
systemctl status "$SERVICE_NAME" --no-pager

echo ""
echo "Installation complete!"
echo ""
echo "Useful commands:"
echo "  Check status:  sudo systemctl status $SERVICE_NAME"
echo "  Start service: sudo systemctl start $SERVICE_NAME"
echo "  Stop service:  sudo systemctl stop $SERVICE_NAME"
echo "  View logs:     sudo journalctl -u $SERVICE_NAME -f"
echo "  Disable boot:  sudo systemctl disable $SERVICE_NAME" 
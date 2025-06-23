# Autossh Systemd Daemon

This directory contains files to run autossh as a reverse tunnel systemd daemon that starts automatically on boot. You can then login remotely as `ssh ubuntu@dansted.org -p 20000` (replace dansted.org with your server).

TODO: Since SystemD is managing this, perhaps `ssh` would suffice in place of `autossh`?

## Files

- `autossh.service` - Systemd service configuration file
- `install-autossh-daemon.sh` - Installation script
- `autossh-service.ps1` - Windows PowerShell service script (alternative)

## Installation

### Prerequisites

1. Make sure autossh is installed on your system:
   ```bash
   # Ubuntu/Debian
   sudo apt-get install autossh
   
   # CentOS/RHEL
   sudo yum install autossh
   
   # Arch Linux
   sudo pacman -S autossh
   ```

2. Ensure SSH key-based authentication is set up for `dansted.org`

### Quick Installation

Run the installation script as root:

```bash
sudo ./install-autossh-daemon.sh
```

### Manual Installation

1. Copy the service file:
   ```bash
   sudo cp autossh.service /etc/systemd/system/
   ```

2. Reload systemd and enable the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable autossh
   sudo systemctl start autossh
   ```

## Service Management

### Check Status
```bash
sudo systemctl status autossh
```

### Start/Stop Service
```bash
sudo systemctl start autossh
sudo systemctl stop autossh
```

### View Logs
```bash
sudo journalctl -u autossh -f
```

### Disable Auto-start
```bash
sudo systemctl disable autossh
```

## Service Configuration

The service is configured to:
- Start automatically on boot
- Restart automatically if it fails
- Wait 10 seconds between restart attempts
- Run as root (required for port forwarding)
- Use security restrictions for better safety

## Troubleshooting

1. **Service fails to start**: Check if autossh is installed and SSH keys are configured
2. **Connection issues**: Verify network connectivity to dansted.org
3. **Permission denied**: Ensure the service file has correct permissions

## Security Notes

- The service runs as root to bind to privileged ports
- Security restrictions are enabled (NoNewPrivileges, PrivateTmp, etc.)
- Consider using a dedicated user if possible for your specific setup 
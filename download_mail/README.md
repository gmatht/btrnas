# Gmail Download Service

This service automatically downloads emails from the Gmail account `gmatht@gmail.com` to a local maildir format using offlineimap.

## Files

- `offlineimap.conf` - Offlineimap configuration file
- `gmail-download.service` - Systemd service file
- `gmail-download.timer` - Systemd timer for periodic sync
- `setup-gmail-download.sh` - Installation and setup script

## Prerequisites

1. Install offlineimap:
   ```bash
   # Ubuntu/Debian
   sudo apt-get install offlineimap
   
   # CentOS/RHEL
   sudo yum install offlineimap
   
   # Arch Linux
   sudo pacman -S offlineimap
   ```

2. Enable IMAP access in your Gmail account:
   - Go to Gmail Settings → Forwarding and POP/IMAP
   - Enable IMAP
   - If you have 2FA enabled, create an App Password

## Installation

### Quick Setup

Run the setup script as the user `gmatht`:

```bash
cd download_mail
chmod +x setup-gmail-download.sh
./setup-gmail-download.sh
```

The script will:
- Create the mail directory (`~/Mail/gmatht`)
- Prompt for your Gmail password
- Install the systemd service and timer
- Start the automatic sync

### Manual Setup

1. Create the mail directory:
   ```bash
   mkdir -p ~/Mail/gmatht
   ```

2. Create password file:
   ```bash
   cat > ~/.offlineimap.py << EOF
   gmatht_password = "your_password_here"
   EOF
   chmod 600 ~/.offlineimap.py
   ```

3. Install service files:
   ```bash
   sudo cp gmail-download.service /etc/systemd/system/
   sudo cp gmail-download.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   ```

4. Enable and start the timer:
   ```bash
   sudo systemctl enable gmail-download.timer
   sudo systemctl start gmail-download.timer
   ```

## Service Management

### Check Status
```bash
# Check timer status
sudo systemctl status gmail-download.timer

# Check service status
sudo systemctl status gmail-download.service
```

### Manual Sync
```bash
sudo systemctl start gmail-download.service
```

### View Logs
```bash
sudo journalctl -u gmail-download.service -f
```

### Disable Auto-sync
```bash
sudo systemctl disable gmail-download.timer
```

## Configuration

### Sync Frequency
The timer is configured to:
- Start syncing 5 minutes after boot
- Sync every 15 minutes thereafter

To change the frequency, edit `gmail-download.timer`:
```ini
OnBootSec=5min          # Wait time after boot
OnUnitActiveSec=15min   # Interval between syncs
```

### Folders
The service downloads all Gmail folders except:
- Spam
- Trash
- Drafts

To modify folder filtering, edit `offlineimap.conf`.

### Mail Location
Emails are stored in: `~/Mail/gmatht/`

## Troubleshooting

### Common Issues

1. **Authentication failed**: 
   - Check your password in `~/.offlineimap.py`
   - If using 2FA, use an App Password instead of your regular password

2. **IMAP not enabled**:
   - Enable IMAP in Gmail Settings → Forwarding and POP/IMAP

3. **Permission denied**:
   - Ensure the service runs as the correct user
   - Check file permissions on `~/.offlineimap.py`

4. **Service fails to start**:
   - Check logs: `sudo journalctl -u gmail-download.service`
   - Verify offlineimap is installed
   - Test configuration: `offlineimap -c offlineimap.conf --dry-run`

### Testing Configuration

Test the offlineimap configuration:
```bash
offlineimap -c offlineimap.conf --dry-run
```

## Security Notes

- The password file (`~/.offlineimap.py`) has restricted permissions (600)
- The service runs as the user `gmatht` with security restrictions
- Consider using OAuth2 for better security (requires additional setup) 
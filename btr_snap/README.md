# BTRFS Snapshot Monitor

A Python script that monitors a BTRFS subvolume for changes and automatically creates snapshots with intelligent retention policies. Includes setup scripts for configuring BTRFS partitions on Raspberry Pi systems.

## Features

- **Automatic Change Detection**: Monitors `/btrfs/home` for changes every 5 minutes
- **Smart Snapshot Types**: Creates snapshots with types MINUTE, HOUR, DAY, MONTH, YEAR based on timing
- **Automatic Cleanup**: Maintains maximum 30 snapshots per type, deleting oldest first
- **Readonly Snapshots**: All snapshots are created as readonly for data protection
- **Configurable**: JSON configuration file for easy customization
- **Systemd Service**: Can run as a system service with automatic restart

## Requirements

- Python 3.6+
- BTRFS filesystem
- Root privileges (for BTRFS operations)
- Linux system with systemd (for service installation)

## Quick Start for Raspberry Pi

### Automated Setup (Recommended)

The easiest way to set up a Raspberry Pi with BTRFS partitions is using the automated installer scripts:

#### Windows Setup

1. **Run the installer:**
   ```cmd
   # Right-click and "Run as administrator"
   install_rpi_imager.bat
   ```

2. The installer will:
   - Download and install Raspberry Pi Imager (if needed)
   - Launch Raspberry Pi Imager for you to write the OS image
   - Wait for you to close Raspberry Pi Imager
   - Automatically create a FAT32 partition to prevent Raspbian from auto-expanding
   - Copy all `.sh` setup scripts to the bootfs partition
   - Configure `firmware/firstboot.sh` to run `setup.sh` on first boot

3. Insert the SD card into your Raspberry Pi and boot it. The setup scripts will run automatically.

#### Linux Setup

1. **Make the script executable:**
   ```bash
   chmod +x install_rpi_imager.sh
   ```

2. **Run the installer:**
   ```bash
   ./install_rpi_imager.sh
   ```

3. The installer will:
   - Detect and install Raspberry Pi Imager (supports apt, dnf, yum, pacman, zypper, or AppImage)
   - Launch Raspberry Pi Imager for you to write the OS image
   - Wait for you to close Raspberry Pi Imager
   - Run `setup_btrfs_partition.sh` to create the BTRFS partition
   - Copy all `.sh` setup scripts to the bootfs partition
   - Configure `firmware/firstboot.sh` to run `setup.sh` on first boot

4. Insert the SD card into your Raspberry Pi and boot it. The setup scripts will run automatically.

### Manual Setup

If you prefer to set up manually:

1. **Write Raspberry Pi OS to SD card** using Raspberry Pi Imager
2. **Create BTRFS partition:**
   - **Linux:** Run `sudo bash setup_btrfs_partition.sh`
   - **Windows:** Run `setup_btrfs_partition.ps1` as Administrator (creates FAT32 partition to reserve space)
3. **Copy setup scripts** to the bootfs partition's `/boot` directory
4. **Edit `firmware/firstboot.sh`** and add: `bash /boot/setup.sh`

## Setup Scripts

### `setup_btrfs_partition.sh` (Linux)

Bash script for Linux systems that:
- Resizes the root partition (mmcblk0p2) to a specified size (default: 3GB)
- Creates a new BTRFS partition using the remaining space
- Formats the partition as BTRFS
- Configures `/etc/fstab` for automatic mounting
- Creates mount point at `/btrfs`

**Usage:**
```bash
sudo bash setup_btrfs_partition.sh
```

The script will prompt for the desired size of partition 2. If partitions 3 or 4 exist, it will show their contents and ask for confirmation before deletion.

### `setup_btrfs_partition.ps1` (Windows)

PowerShell script for Windows that:
- Finds the boot/EFI partition and identifies its disk
- Creates a new FAT32 partition using all available unallocated space
- Automatically assigns a drive letter
- Prevents Raspbian from automatically expanding into unallocated space

**Usage:**
```powershell
# Run as Administrator
.\setup_btrfs_partition.ps1
```

**Note:** This script creates a FAT32 partition, not BTRFS. The actual BTRFS partition should be created on the Raspberry Pi itself using `setup_btrfs_partition.sh`.

### `install_rpi_imager.bat` (Windows)

Batch script that automates the entire setup process on Windows:
- Downloads and installs Raspberry Pi Imager if needed
- Launches Raspberry Pi Imager
- After closing, runs `setup_btrfs_partition.ps1`
- Finds the bootfs partition and copies all `.sh` files to `/boot`
- Updates `firmware/firstboot.sh` to run `setup.sh` on first boot

**Usage:**
```cmd
# Right-click and "Run as administrator"
install_rpi_imager.bat
```

### `install_rpi_imager.sh` (Linux)

Bash script that automates the entire setup process on Linux:
- Detects and installs Raspberry Pi Imager (supports multiple package managers)
- Launches Raspberry Pi Imager
- After closing, runs `setup_btrfs_partition.sh`
- Finds the bootfs partition and copies all `.sh` files to `/boot`
- Updates `firmware/firstboot.sh` to run `setup.sh` on first boot

**Usage:**
```bash
chmod +x install_rpi_imager.sh
./install_rpi_imager.sh
```

## Installation

1. **Copy the script to a suitable location:**
   ```bash
   sudo cp btrfs_snapshot_monitor.py /usr/local/bin/
   sudo chmod +x /usr/local/bin/btrfs_snapshot_monitor.py
   ```

2. **Create configuration directory and file:**
   ```bash
   sudo mkdir -p /etc
   sudo cp btrfs_snapshot_monitor.conf /etc/
   ```

3. **Edit the configuration file:**
   ```bash
   sudo nano /etc/btrfs_snapshot_monitor.conf
   ```

4. **Install as systemd service (optional):**
   ```bash
   sudo cp btrfs-snapshot-monitor.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable btrfs-snapshot-monitor.service
   sudo systemctl start btrfs-snapshot-monitor.service
   ```

## Configuration

The configuration file (`/etc/btrfs_snapshot_monitor.conf`) supports the following options:

```json
{
    "source_subvolume": "/btrfs/home",
    "snapshot_dir": "/btrfs/snapshot",
    "check_interval": 300,
    "max_snapshots_per_type": 30,
    "log_level": "INFO",
    "log_file": "/var/log/btrfs_snapshot_monitor.log"
}
```

### Configuration Options

- `source_subvolume`: Path to the BTRFS subvolume to monitor
- `snapshot_dir`: Directory where snapshots will be stored
- `check_interval`: Time between checks in seconds (default: 300 = 5 minutes)
- `max_snapshots_per_type`: Maximum number of snapshots to keep per type
- `log_level`: Logging level (DEBUG, INFO, WARNING, ERROR)
- `log_file`: Path to log file

## Usage

### Manual Execution

```bash
# Run with default configuration
sudo python3 btrfs_snapshot_monitor.py

# Run with custom configuration file
sudo python3 btrfs_snapshot_monitor.py --config /path/to/config.json

# Run in dry-run mode (no actual snapshots created)
sudo python3 btrfs_snapshot_monitor.py --dry-run
```

### Systemd Service Management

```bash
# Start the service
sudo systemctl start btrfs-snapshot-monitor.service

# Stop the service
sudo systemctl stop btrfs-snapshot-monitor.service

# Check service status
sudo systemctl status btrfs-snapshot-monitor.service

# View logs
sudo journalctl -u btrfs-snapshot-monitor.service -f

# Enable service to start on boot
sudo systemctl enable btrfs-snapshot-monitor.service
```

## Snapshot Naming Convention

Snapshots are named using the format: `YYYYMMDD_HHMMSS_TYPE`

Examples:
- `20241201_143022_MINUTE` - Minute-level snapshot
- `20241201_140000_HOUR` - Hour-level snapshot
- `20241201_000000_DAY` - Day-level snapshot
- `20241201_000000_MONTH` - Month-level snapshot
- `20241201_000000_YEAR` - Year-level snapshot

## Snapshot Type Logic

## Retention Policy

- Maximum 30 snapshots per type
- Oldest snapshots are automatically deleted when limit is exceeded
- Each type is managed independently

## Monitoring and Logging

The script logs all activities to both:
- Console output (stdout)
- Log file (configurable, default: `/var/log/btrfs_snapshot_monitor.log`)

Log entries include:
- Service start/stop events
- Change detection
- Snapshot creation
- Snapshot deletion
- Errors and warnings

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure the script runs as root or has appropriate BTRFS permissions
2. **BTRFS Command Not Found**: Install BTRFS tools: `sudo apt install btrfs-progs` (Ubuntu/Debian)
3. **Directory Not Found**: Ensure the source subvolume and snapshot directory exist
4. **Service Won't Start**: Check systemd logs: `sudo journalctl -u btrfs-snapshot-monitor.service`

### Debug Mode

Run with debug logging to see detailed information:

```bash
# Edit config file to set log_level to DEBUG
sudo nano /etc/btrfs_snapshot_monitor.conf

# Or run manually with debug output
sudo python3 btrfs_snapshot_monitor.py --config /etc/btrfs_snapshot_monitor.conf
```

## Security Considerations

- The script requires root privileges for BTRFS operations
- All snapshots are created as readonly to prevent accidental modification
- The systemd service includes security hardening options
- Log files may contain sensitive information about file system structure

## Accessing Snapshots via FTP and SMB

### Setup

To allow users to access BTRFS snapshots via vsftpd (FTP) and Samba (SMB), run the installation script:

```bash
sudo bash install_vsftpd_samba.sh
```

This script will:
- Install vsftpd and Samba packages
- Configure vsftpd to share `/btrfs` directory
- Configure Samba with `[btrfs]` and `[homes]` shares
- Set up proper permissions
- Configure firewall rules
- Start and enable services

### Manual Configuration

If you prefer to configure manually:

1. **Copy configuration files:**
   ```bash
   sudo cp vsftpd.conf.example /etc/vsftpd.conf
   sudo cp smb.conf.example /etc/samba/smb.conf
   ```

2. **Set up permissions:**
   ```bash
   sudo bash setup_btrfs_permissions.sh
   ```

3. **Start services:**
   ```bash
   sudo systemctl enable vsftpd samba
   sudo systemctl start vsftpd smbd nmbd
   ```

### Access Methods

**FTP (vsftpd):**
- Connect to the server via FTP
- Users are chrooted to `/btrfs`
- Navigate to:
  - `/@home/username/` - Your home directory (read-write)
  - `/snapshot/` - Snapshot directory (read-only, enforced by BTRFS)

**SMB (Samba):**
- **BTRFS share**: `\\server\btrfs`
  - Navigate to `@home/username/` for home directory (read-write)
  - Navigate to `snapshot/` for snapshots (read-only)
- **Homes share**: `\\server\username`
  - Direct access to your home directory (read-write)

### Security Notes

- **Path Traversal Prevention**: vsftpd uses chroot to jail users to `/btrfs`
- **BTRFS Read-Only**: Snapshots are created with `-r` flag, so they cannot be modified even if services allow writes
- **Directory Permissions**: Users can browse snapshots but only access their own home subdirectories
- **Authentication**: System user accounts required for both services

### Running Permission Script After New Snapshots

After new snapshots are created, run the permissions script to ensure proper access:

```bash
sudo bash setup_btrfs_permissions.sh
```

You can automate this by adding it to the snapshot monitor script or running it as a cron job.

## Windows Users Backup to Samba

### Overview

A simple backup solution to continuously sync `C:\Users` from Windows machines to the Linux Samba share. Uses Windows built-in `robocopy` tool with no external dependencies.

### Quick Start

1. **Run the installer:**
   ```powershell
   # Right-click and "Run as administrator"
   cd windows_backup_client
   .\install_windows_backup.ps1
   ```

2. The installer will:
   - Prompt for Samba share path (e.g., `\\server\btrfs\backups\users`)
   - Prompt for credentials if needed
   - Ask for backup method (scheduled or continuous)
   - Create a Windows scheduled task to run the backup automatically

3. **Start the backup:**
   ```powershell
   Start-ScheduledTask -TaskName "WindowsUsersBackupToSamba"
   ```

### Manual Usage

**PowerShell Script:**
```powershell
.\backup_users_to_samba.ps1 -DestinationShare "\\server\btrfs\backups\users" -IntervalMinutes 5
```

**Batch File:**
```cmd
# Edit backup_users_to_samba.bat to set DEST variable, then run:
backup_users_to_samba.bat
```

### Configuration Options

**Scheduled Mode (Recommended):**
- Runs backup every N minutes (default: 5 minutes)
- More reliable and easier to manage
- Can be stopped/started via Task Scheduler

**Continuous Mode:**
- Monitors for changes continuously using robocopy `/MON:1`
- Syncs immediately when changes are detected
- Runs until manually stopped

### Excluded Directories

The backup automatically excludes common temporary and cache directories:
- `AppData\Local\Temp`
- `AppData\Local\Microsoft\Windows\INetCache`
- `AppData\Local\Microsoft\Windows\WebCache`
- `AppData\Roaming\Microsoft\Windows\Recent`
- `$Recycle.Bin`

### Managing the Backup

**Check task status:**
```powershell
Get-ScheduledTask -TaskName "WindowsUsersBackupToSamba" | Get-ScheduledTaskInfo
```

**View logs:**
```powershell
Get-Content windows_backup_client\backup_log.txt -Tail 50
```

**Stop the backup:**
```powershell
Stop-ScheduledTask -TaskName "WindowsUsersBackupToSamba"
```

**Uninstall:**
```powershell
.\install_windows_backup.ps1 -Uninstall
```

### Troubleshooting

1. **"Cannot access share"**: Ensure the Samba share is accessible and credentials are correct
2. **"Access denied"**: Run the installer as Administrator
3. **Backup not running**: Check Task Scheduler and ensure the task is enabled
4. **Network disconnections**: The script will retry automatically (3 retries with 5 second wait)

### Security Notes

- Credentials are stored in the scheduled task (encrypted by Windows)
- Consider using a dedicated backup user account on the Samba server
- The backup runs with the user's permissions (may need admin for some files)

## Linux Client Backup to Samba

### Overview

A continuous backup solution using `lsyncd` to sync local directories (e.g., `/home`) to the Samba share. Uses real-time file monitoring and rsync for efficient synchronization. Automatically starts on boot via systemd.

### Quick Start

1. **Run the installer:**
   ```bash
   cd linux_backup_client
   sudo bash install_linux_backup.sh
   ```

2. The installer will:
   - Install lsyncd, cifs-utils, and rsync packages
   - Prompt for Samba server, share name, and credentials
   - Prompt for source directory (default: `/home`)
   - Create secure credentials file
   - Set up Samba mount as systemd service
   - Configure lsyncd for continuous sync
   - Enable services to start on boot

3. **Verify the setup:**
   ```bash
   systemctl status lsyncd-backup
   systemctl status mnt-samba-backup.mount
   ```

### How It Works

- **lsyncd**: Monitors the source directory for changes using inotify
- **Samba Mount**: Mounts the Samba share at `/mnt/samba-backup` using systemd
- **rsync**: Syncs changes efficiently to the mounted share
- **Systemd Services**: Both mount and lsyncd run as systemd services, starting automatically on boot

### Configuration

The main configuration file is located at `/etc/lsyncd/lsyncd.conf.lua`. Key settings:

- **Source directory**: Default is `/home`, can be changed during installation
- **Target**: `/mnt/samba-backup` (mounted Samba share)
- **Exclude patterns**: Automatically excludes cache, temp files, trash, etc.
- **Sync delay**: 5 seconds (configurable)

### Managing the Backup

**Check service status:**
```bash
systemctl status lsyncd-backup
systemctl status mnt-samba-backup.mount
```

**View logs:**
```bash
# lsyncd logs
tail -f /var/log/lsyncd/lsyncd.log

# Service logs
journalctl -u lsyncd-backup -f
journalctl -u mnt-samba-backup.mount -f
```

**Restart services:**
```bash
systemctl restart lsyncd-backup
systemctl restart mnt-samba-backup.mount
```

**Stop/Start services:**
```bash
systemctl stop lsyncd-backup
systemctl start lsyncd-backup
```

**Manually mount/unmount Samba share:**
```bash
# Mount
systemctl start mnt-samba-backup.mount

# Unmount
systemctl stop mnt-samba-backup.mount
```

### Troubleshooting

1. **"Cannot mount Samba share"**: 
   - Check network connectivity: `ping <samba-server>`
   - Verify credentials in `/etc/samba/backup-credentials`
   - Test mount manually: `sudo mount -t cifs //server/share /mnt/samba-backup -o credentials=/etc/samba/backup-credentials`

2. **"lsyncd not syncing"**:
   - Check if mount is active: `systemctl status mnt-samba-backup.mount`
   - Check lsyncd logs: `tail -f /var/log/lsyncd/lsyncd.log`
   - Verify configuration: `lsyncd -nodaemon -config /etc/lsyncd/lsyncd.conf.lua`

3. **"Permission denied"**:
   - Check mount permissions: `ls -la /mnt/samba-backup`
   - Verify credentials file permissions (should be 600): `ls -l /etc/samba/backup-credentials`

4. **"Service won't start"**:
   - Check dependencies: `systemctl list-dependencies lsyncd-backup`
   - Check mount status: `mountpoint /mnt/samba-backup`
   - View detailed logs: `journalctl -u lsyncd-backup -n 50`

### Security Notes

- Credentials are stored in `/etc/samba/backup-credentials` with 600 permissions (root only)
- Consider using a dedicated backup user account on the Samba server
- The Samba share is mounted with appropriate file/directory permissions (0664/0775)
- lsyncd runs as root to access all files in the source directory

### Excluded Directories

The backup automatically excludes:
- Cache directories (`.cache`, browser caches)
- Temporary files (`.tmp`, `.temp`)
- Trash directories (`.Trash`, `.local/share/Trash`)
- System files (`.thumbnails`, `.Xauthority`)
- Package manager caches (`.npm`, `.pip`, `.cargo`)

You can modify exclusions in `/etc/lsyncd/lsyncd.conf.lua`.

## File Structure

```
btr_snap/
├── btrfs_snapshot_monitor.py      # Main Python monitoring script
├── btrfs_snapshot_monitor.conf     # Configuration file
├── btrfs-snapshot-monitor.service  # Systemd service file
├── setup_btrfs_partition.sh        # Linux: Create BTRFS partition
├── setup_btrfs_partition.ps1       # Windows: Create FAT32 partition
├── install_rpi_imager.bat          # Windows: Automated setup
├── install_rpi_imager.sh           # Linux: Automated setup
├── install_btrfs_monitor.sh        # Install monitor as service
├── install_vsftpd_samba.sh         # Install and configure vsftpd/Samba
├── setup_btrfs_permissions.sh      # Set permissions on /btrfs structure
├── vsftpd.conf.example             # vsftpd configuration template
├── smb.conf.example                # Samba configuration template
├── setup.sh                        # Setup script (runs on first boot)
├── configure_services.sh           # Configure system services
├── windows_backup_client/          # Windows backup client
│   ├── backup_users_to_samba.ps1   # PowerShell backup script
│   ├── backup_users_to_samba.bat   # Batch file backup script
│   └── install_windows_backup.ps1  # Installation script
├── linux_backup_client/            # Linux backup client
│   ├── lsyncd.conf                 # lsyncd configuration template
│   ├── mount_samba.sh              # Samba mount helper script
│   ├── install_linux_backup.sh     # Installation script
│   └── lsyncd-backup.service       # Systemd service file
└── README.md                       # This file
```

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve the script. 
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
├── setup.sh                        # Setup script (runs on first boot)
├── configure_services.sh           # Configure system services
└── README.md                       # This file
```

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve the script. 
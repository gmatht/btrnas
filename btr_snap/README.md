# BTRFS Snapshot Monitor

A Python script that monitors a BTRFS subvolume for changes and automatically creates snapshots with intelligent retention policies.

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

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve the script. 
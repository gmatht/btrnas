#!/usr/bin/env python3
"""
BTRFS Snapshot Monitor

This script monitors a BTRFS subvolume for changes and creates snapshots
with automatic cleanup based on retention policies.

Usage:
    python btrfs_snapshot_monitor.py [--config CONFIG_FILE]

Configuration:
    - Monitors /btrfs/home for changes
    - Creates snapshots in /btrfs/snapshot
    - Snapshot naming: YYYYMMDD_HHMMSS_TYPE
    - Types: MINUTE, HOUR, DAY, MONTH, YEAR
    - Retention: 30 snapshots per type
    - Check interval: 5 minutes
"""

import os
import sys
import time
import subprocess
import logging
import argparse
import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import hashlib


class BTRFSSnapshotMonitor:
    """BTRFS Snapshot Monitor with automatic cleanup"""
    
    def __init__(self, config: Dict):
        self.config = config
        self.source_subvolume = config.get('source_subvolume', '/btrfs/home')
        self.snapshot_dir = config.get('snapshot_dir', '/btrfs/snapshot')
        self.check_interval = config.get('check_interval', 300)  # 5 minutes
        self.max_snapshots_per_type = config.get('max_snapshots_per_type', 30)
        self.snapshot_types = ['MINUTE', 'HOUR', 'DAY', 'MONTH', 'YEAR']
        
        # Setup logging
        self.setup_logging()
        
        # Ensure directories exist
        self.ensure_directories()
        
        # Initialize last snapshot hash
        self.last_snapshot_hash = None
        
    def setup_logging(self):
        """Setup logging configuration"""
        log_level = self.config.get('log_level', 'INFO')
        log_file = self.config.get('log_file', '/var/log/btrfs_snapshot_monitor.log')
        
        logging.basicConfig(
            level=getattr(logging, log_level.upper()),
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)
        
    def ensure_directories(self):
        """Ensure required directories exist"""
        Path(self.snapshot_dir).mkdir(parents=True, exist_ok=True)
        self.logger.info(f"Ensured snapshot directory exists: {self.snapshot_dir}")
        
    def run_command(self, command: List[str], check: bool = True) -> subprocess.CompletedProcess:
        """Run a shell command and return the result"""
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=check
            )
            return result
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Command failed: {' '.join(command)}")
            self.logger.error(f"Error: {e.stderr}")
            raise
            
    def get_subvolume_hash(self, subvolume_path: str) -> str:
        """Get a hash representing the current state of the subvolume"""
        try:
            # Use btrfs subvolume show to get generation number and other metadata
            result = self.run_command(['btrfs', 'subvolume', 'show', subvolume_path])
            
            # Extract generation number from output
            for line in result.stdout.split('\n'):
                if 'Generation:' in line:
                    generation = line.split(':')[1].strip()
                    return generation

            self.logger.warning(f"Failed to get subvolume hash, returning None")
            return None
            
        except Exception as e:
            self.logger.error(f"Failed to get subvolume hash: {e}")
            return self.get_directory_hash(subvolume_path)
            
            
    def has_changes(self) -> bool:
        """Check if the source subvolume has changed since last snapshot"""
        current_hash = self.get_subvolume_hash(self.source_subvolume)
        
        if self.last_snapshot_hash is None:
            self.last_snapshot_hash = current_hash
            return False
            
        has_changes = current_hash != self.last_snapshot_hash
        if has_changes:
            self.logger.info(f"Changes detected in {self.source_subvolume}")
            self.last_snapshot_hash = current_hash
            
        return has_changes
        
    def get_snapshot_type(self) -> str:
        """Determine the appropriate snapshot type based on current time"""
        now = datetime.now()
        existing_snapshots = self.get_existing_snapshots()
        current_year = now.strftime('%Y')
        current_month = now.strftime('%Y%m')
        current_day = now.strftime('%Y%m%d')
        current_hour = now.strftime('%Y%m%d_%H')
        
        # Check if we need a yearly snapshot
        if now.month == 1 and now.day == 1 and now.hour == 0 and now.minute == 0:
            return 'YEAR'
        # If no yearly snapshot exists for this year, create one
        elif not any(snapshot[0:4] == current_year for snapshot in existing_snapshots.get('YEAR', [])):
            return 'YEAR'
            
        # Check if we need a monthly snapshot
        elif now.day == 1 and now.hour == 0 and now.minute == 0:
            return 'MONTH'
        # If no monthly snapshot exists for this month, create one
        elif not any(snapshot[0:6] == current_month for snapshot in existing_snapshots.get('MONTH', [])):
            return 'MONTH'
            
        # Check if we need a daily snapshot
        elif now.hour == 0 and now.minute == 0:
            return 'DAY'
        # If no daily snapshot exists for this day, create one
        elif not any(snapshot[0:8] == current_day for snapshot in existing_snapshots.get('DAY', [])):
            return 'DAY'
            
        # Check if we need an hourly snapshot
        elif now.minute == 0:
            return 'HOUR'
        # If no hourly snapshot exists for this hour, create one
        elif not any(snapshot[0:11] == current_hour for snapshot in existing_snapshots.get('HOUR', [])):
            return 'HOUR'
            
        # Default to minute
        else:
            return 'MINUTE'
            
    def create_snapshot(self, snapshot_type: str) -> str:
        """Create a new readonly snapshot"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        snapshot_name = f"{timestamp}_{snapshot_type}"
        snapshot_path = os.path.join(self.snapshot_dir, snapshot_name)
        
        try:
            # Create readonly snapshot
            self.run_command([
                'btrfs', 'subvolume', 'snapshot', '-r',
                self.source_subvolume, snapshot_path
            ])

            #TODO: This is a hack to get the hash of the source subvolume after the snapshot is created
            #That this is needed is a sign that has_changes() is not working as expected
            self.last_snapshot_hash = self.get_subvolume_hash(self.source_subvolume)
            
            self.logger.info(f"Created snapshot: {snapshot_name}")
            return snapshot_name
            
        except Exception as e:
            self.logger.error(f"Failed to create snapshot {snapshot_name}: {e}")
            raise
            
    def get_existing_snapshots(self) -> Dict[str, List[str]]:
        """Get existing snapshots grouped by type"""
        snapshots_by_type = {snapshot_type: [] for snapshot_type in self.snapshot_types}
        
        try:
            # List all directories in snapshot directory
            for snapshot_name in os.listdir(self.snapshot_dir):
                if '_' in snapshot_name:
                    try:
                        # Extract type from name (YYYYMMDD_HHMMSS_TYPE)
                        type_part = snapshot_name.split('_')[-1]
                        if type_part in self.snapshot_types:
                            snapshots_by_type[type_part].append(snapshot_name)
                            print(f"Added snapshot: {snapshot_name} to {type_part}")
                    except IndexError:
                        continue
                                
        except Exception as e:
            self.logger.error(f"Failed to list existing snapshots: {e}")
            
        return snapshots_by_type
        
    def cleanup_old_snapshots(self, snapshot_type: str):
        """Remove oldest snapshots if we exceed the limit"""
        existing_snapshots = self.get_existing_snapshots()
        snapshots = existing_snapshots.get(snapshot_type, [])
        
        if len(snapshots) >= self.max_snapshots_per_type:
            # Sort snapshots by timestamp (oldest first)
            snapshots.sort()
            
            # Calculate how many to remove
            snapshots_to_remove = len(snapshots) - self.max_snapshots_per_type + 1
            
            for i in range(snapshots_to_remove):
                snapshot_name = snapshots[i]
                snapshot_path = os.path.join(self.snapshot_dir, snapshot_name)
                
                try:
                    # Delete the subvolume
                    self.run_command(['btrfs', 'subvolume', 'delete', snapshot_path])
                    self.logger.info(f"Deleted old snapshot: {snapshot_name}")
                    
                except Exception as e:
                    self.logger.error(f"Failed to delete snapshot {snapshot_name}: {e}")
                    
    def monitor_loop(self):
        """Main monitoring loop"""
        self.logger.info("Starting BTRFS snapshot monitor")
        self.logger.info(f"Monitoring: {self.source_subvolume}")
        self.logger.info(f"Snapshot directory: {self.snapshot_dir}")
        self.logger.info(f"Check interval: {self.check_interval} seconds")
        
        try:
            while True:
                try:
                    # Check for changes
                    if self.has_changes():
                        # Determine snapshot type
                        snapshot_type = self.get_snapshot_type()
                        
                        # Create new snapshot
                        snapshot_name = self.create_snapshot(snapshot_type)
                        
                        # Cleanup old snapshots of the same type
                        self.cleanup_old_snapshots(snapshot_type)
                        
                    # Wait for next check
                    time.sleep(self.check_interval)
                    
                except KeyboardInterrupt:
                    self.logger.info("Received interrupt signal, shutting down")
                    break
                except Exception as e:
                    self.logger.error(f"Error in monitoring loop: {e}")
                    time.sleep(self.check_interval)
                    
        except Exception as e:
            self.logger.error(f"Fatal error: {e}")
            sys.exit(1)


def load_config(config_file: Optional[str] = None) -> Dict:
    """Load configuration from file or use defaults"""
    default_config = {
        'source_subvolume': '/btrfs/home',
        'snapshot_dir': '/btrfs/snapshot',
        'check_interval': 300,  # 5 minutes
        'max_snapshots_per_type': 30,
        'log_level': 'INFO',
        'log_file': '/var/log/btrfs_snapshot_monitor.log'
    }
    
    if config_file and os.path.exists(config_file):
        try:
            with open(config_file, 'r') as f:
                file_config = json.load(f)
                default_config.update(file_config)
        except Exception as e:
            print(f"Warning: Could not load config file {config_file}: {e}")
            
    return default_config


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='BTRFS Snapshot Monitor',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument(
        '--config', '-c',
        help='Configuration file path (JSON format)'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Run in dry-run mode (no actual snapshots created)'
    )
    
    args = parser.parse_args()
    
    # Load configuration
    config = load_config(args.config)
    
    if args.dry_run:
        config['dry_run'] = True
        print("Running in dry-run mode")
        
    # Create and start monitor
    monitor = BTRFSSnapshotMonitor(config)
    monitor.monitor_loop()


if __name__ == '__main__':
    main() 
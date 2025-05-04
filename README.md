# LXC Container Backup Script

#### Description

This Bash script automates the process of creating, managing, and uploading backups of LXC (Linux Containers) to MEGA cloud storage. It's designed to maintain a specified number of local backups, MEGA backups, and LXC snapshots.

#### Features

- **Automatic error handling**: The script uses `set -e` and a trap to exit on errors.
- **Logging**: Provides detailed logging of each step in the backup process.
- **Dependency checking**: Verifies the presence of required commands before execution.
- **MEGA integration**: Automatically creates a backup folder on MEGA if it doesn't exist.
- **Snapshot management**: Cleans up old snapshots, maintaining a specified count.
- **Backup rotation**: Manages both local and MEGA backups, keeping only the most recent ones.
- **Compression**: Uses `xz` compression for efficient storage and transfer.

#### How It Works
For XZ-arcive
```
sudo apt install xz -y
```

1. **Initialization**: 
   - Sets up error handling and logging.
   - Checks for required commands and the existence of the specified container.

2. **MEGA Setup**: 
   - Ensures a backup folder exists on MEGA. https://mega.io/ru/cmd#download

3. **Snapshot Management**:
   - Removes old snapshots, keeping only the specified number.

4. **Backup Creation and Upload**:
   - Creates a new snapshot of the container.
   - Exports the snapshot to a compressed archive.
   - Uploads the archive to MEGA.

5. **Cleanup**:
   - Removes old local backups and MEGA backups, maintaining the specified count.

#### How to Restore a Container

To restore a container from a backup:

1. **Download the backup**:
   - Use the MEGA client to download the desired `.tar.gz.xz` file.

2. **Decompress the archive**:
   ```bash
   xz -d <container_name>-<timestamp>.tar.gz.xz
   ```

3. **Import the container**:
   ```bash
   lxc import <container_name>-<timestamp>.tar.gz
   ```

4. **Start the restored container**:
   ```bash
   lxc start <container_name>
   ```

#### Configuration

Adjust the following variables in the script to customize the backup process:

- `CONTAINER`: Name of the LXC container to backup.
- `LOCAL_BACKUP_COUNT`: Number of local backups to keep.
- `MEGA_BACKUP_COUNT`: Number of backups to keep on MEGA.
- `SNAPSHOT_COUNT`: Number of snapshots to keep in LXC.

#### Requirements

- LXC (Linux Containers)
- MEGA command-line tools (`mega-put`, `mega-ls`, `mega-mkdir`)
- `xz` compression utility

#### Error Handling

The script uses the `trap` command to handle errors gracefully. If an error occurs, it will display an error message and exit with a non-zero status.

#### Note

Ensure you have sufficient permissions and storage space both locally and on your MEGA account before running this script.

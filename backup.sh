#!/bin/bash
set -e
set -x

trap 'echo "An error occurred. Exiting..."; exit 1' ERR

CONTAINER="you-lxc-conteiner"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="${SCRIPT_DIR}/tmp"
LOCAL_BACKUP_COUNT=3  # Number of local backups to keep
MEGA_BACKUP_COUNT=3   # Number of backups to keep on MEGA
SNAPSHOT_COUNT=3      # Number of snapshots to keep in LXC


echo "Starting backup process for container: $CONTAINER"
echo "Current date and time: $(date)"
echo "LXC version: $(lxc --version)"
echo "Container status:"
lxc info $CONTAINER | grep Status


# Check for required commands
for cmd in lxc xz mega-put mega-ls mega-mkdir; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed or not in PATH"
        exit 1
    fi
done

# Check if the container exists
if ! lxc info $CONTAINER &>/dev/null; then
    echo "Container $CONTAINER does not exist"
    exit 1
fi

mkdir -p "$TMP_DIR"

# Check and create backup folder on MEGA
if ! mega-ls / | grep -q '^backup$'; then
    echo "Backup folder not found on MEGA. Creating..."
    if mega-mkdir /backup; then
        echo "Backup folder successfully created on MEGA."
    else
        echo "Error creating backup folder on MEGA. Exiting..."
        exit 1
    fi
else
    echo "Backup folder already exists on MEGA."
fi

cleanup_old_snapshots() {
    echo "Cleaning up old snapshots..."
    
    # Check if there are any snapshots
    if ! lxc info $CONTAINER | grep -q "Snapshots:"; then
        echo "No snapshots found for $CONTAINER"
        return
    fi
    
    snapshots=($(lxc info $CONTAINER | sed -n '/Snapshots:/,/^$/p' | grep '|' | awk -F'|' '{print $2}' | awk '{$1=$1};1' | grep -v '^NAME'))
    
    if [ ${#snapshots[@]} -eq 0 ]; then
        echo "No snapshots found for $CONTAINER"
        return
    fi
    
    echo "Current number of snapshots: ${#snapshots[@]}"
    
    if [ ${#snapshots[@]} -gt $SNAPSHOT_COUNT ]; then
        to_delete=$(( ${#snapshots[@]} - $SNAPSHOT_COUNT ))
        echo "Deleting $to_delete old snapshots"
        for ((i=0; i<$to_delete; i++)); do
            echo "Deleting snapshot: ${snapshots[i]}"
            lxc delete "$CONTAINER/${snapshots[i]}"
        done
    else
        echo "No need to delete snapshots. Current count is within the limit."
    fi
}


cleanup_old_files() {
    echo "Cleaning up old files in $TMP_DIR..."
    find "$TMP_DIR" -name "${CONTAINER}-*.tar.gz*" -type f -delete
}

create_and_upload_snapshot() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local snapshot_name="snap-${timestamp}"
    local archive_name="${CONTAINER}-${timestamp}.tar.gz"
    local archive_path="${TMP_DIR}/${archive_name}"

    echo "Creating snapshot for $CONTAINER..."
    lxc snapshot $CONTAINER "${snapshot_name}"

    echo "Exporting snapshot to $archive_path..."
    lxc export "${CONTAINER}" "$archive_path" --instance-only

    if [ ! -f "$archive_path" ]; then
        echo "Failed to create backup file"
        return 1
    fi

    echo "Compressing $archive_path..."
    xz -9 "$archive_path"
    local compressed_archive="${archive_path}.xz"

    echo "Uploading $compressed_archive to MEGA..."
    if ! mega-put "$compressed_archive" /backup/; then
        echo "Failed to upload $compressed_archive to MEGA"
        return 1
    fi

    echo "Snapshot created and uploaded successfully."
}

cleanup_old_backups() {
    echo "Cleaning up old backups..."
    
    # Clean up local backups
    local_backups=($(ls -t ${TMP_DIR}/${CONTAINER}-*.tar.gz.xz))
    if [ ${#local_backups[@]} -gt $LOCAL_BACKUP_COUNT ]; then
        for ((i=$LOCAL_BACKUP_COUNT; i<${#local_backups[@]}; i++)); do
            rm "${local_backups[i]}"
        done
    fi

    # Clean up MEGA backups
    mega_backups=($(mega-ls /backup/ | grep ${CONTAINER} | awk '{print $1}'))
    if [ ${#mega_backups[@]} -gt $MEGA_BACKUP_COUNT ]; then
        for ((i=$MEGA_BACKUP_COUNT; i<${#mega_backups[@]}; i++)); do
            mega-rm "/backup/${mega_backups[i]}"
        done
    fi
}

cleanup_old_snapshots
cleanup_old_files
create_and_upload_snapshot
cleanup_old_backups

echo "Backup process completed."

#!/bin/bash
set -e
#set -x

trap 'echo "Error occurred in line $LINENO. Exiting..."; exit 1' ERR

CONTAINER="container_name"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="${SCRIPT_DIR}/tmp"
LOCAL_BACKUP_COUNT=2
MEGA_BACKUP_COUNT=3
SNAPSHOT_COUNT=2

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting backup process for container: $CONTAINER"
log "LXC version: $(lxc --version)"
log "Container status:"
lxc info $CONTAINER | grep Status

for cmd in lxc xz mega-put mega-ls mega-mkdir; do
    if ! command -v $cmd &> /dev/null; then
        log "Error: $cmd is not installed or not in PATH"
        exit 1
    fi
done

if ! lxc info $CONTAINER &>/dev/null; then
    log "Container $CONTAINER does not exist"
    exit 1
fi

mkdir -p "$TMP_DIR"

if ! mega-ls / | grep -q '^backup$'; then
    log "Backup folder not found on MEGA. Creating..."
    if mega-mkdir /backup; then
        log "Backup folder successfully created on MEGA."
    else
        log "Error creating backup folder on MEGA. Exiting..."
        exit 1
    fi
else
    log "Backup folder already exists on MEGA."
fi

cleanup_old_snapshots() {
    log "Cleaning up old snapshots..."
    
    if ! lxc info $CONTAINER | grep -q "Snapshots:"; then
        log "No snapshots found for $CONTAINER"
        return
    fi
    
    snapshots=($(lxc info $CONTAINER | sed -n '/Snapshots:/,/^$/p' | grep '|' | awk -F'|' '{print $2}' | awk '{$1=$1};1' | grep -v '^NAME'))
    
    if [ ${#snapshots[@]} -eq 0 ]; then
        log "No snapshots found for $CONTAINER"
        return
    fi
    
    log "Current number of snapshots: ${#snapshots[@]}"
    
    if [ ${#snapshots[@]} -gt $SNAPSHOT_COUNT ]; then
        to_delete=$(( ${#snapshots[@]} - $SNAPSHOT_COUNT ))
        log "Deleting $to_delete old snapshots"
        for ((i=0; i<$to_delete; i++)); do
            log "Deleting snapshot: ${snapshots[i]}"
            if ! lxc delete "$CONTAINER/${snapshots[i]}"; then
                log "Failed to delete snapshot ${snapshots[i]}"
            fi
        done
    else
        log "No need to delete snapshots. Current count is within the limit."
    fi
}

cleanup_old_files() {
    log "Cleaning up old files in $TMP_DIR..."
    find "$TMP_DIR" -name "${CONTAINER}-*.tar.gz*" -type f -delete
}

create_and_upload_snapshot() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local snapshot_name="snap-${timestamp}"
    local archive_name="${CONTAINER}-${timestamp}.tar.gz"
    local archive_path="${TMP_DIR}/${archive_name}"

    log "Creating snapshot for $CONTAINER..."
    if ! lxc snapshot $CONTAINER "${snapshot_name}"; then
        log "Failed to create snapshot"
        return 1
    fi

    log "Exporting snapshot to $archive_path..."
    if ! lxc export "${CONTAINER}" "$archive_path" --instance-only; then
        log "Failed to export snapshot"
        return 1
    fi

    if [ ! -f "$archive_path" ]; then
        log "Failed to create backup file"
        return 1
    fi

    log "Compressing $archive_path..."
    if ! xz -9 "$archive_path"; then
        log "Failed to compress backup file"
        return 1
    fi
    local compressed_archive="${archive_path}.xz"

    log "Uploading $compressed_archive to MEGA..."
    if ! mega-put "$compressed_archive" /backup/; then
        log "Failed to upload $compressed_archive to MEGA"
        return 1
    fi

    log "Snapshot created and uploaded successfully."
}

cleanup_old_backups() {
    log "Cleaning up old backups..."
    
    # Ensure backup directory exists
    mkdir -p "${SCRIPT_DIR}/backup"
    
    # Move files from tmp to backup
    log "Moving files from ${TMP_DIR} to ${SCRIPT_DIR}/backup"
    mv "${TMP_DIR}"/${CONTAINER}-*.tar.gz.xz "${SCRIPT_DIR}/backup/" 2>/dev/null || true
    
    # Clean up local backups
    log "Cleaning up local backups in ${SCRIPT_DIR}/backup"
    local_backups=($(find "${SCRIPT_DIR}/backup" -name "${CONTAINER}-*.tar.gz.xz" -type f -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-))
    
    log "Found ${#local_backups[@]} local backups"
    
    if [ ${#local_backups[@]} -gt $LOCAL_BACKUP_COUNT ]; then
        log "Keeping $LOCAL_BACKUP_COUNT most recent local backups"
        for ((i=$LOCAL_BACKUP_COUNT; i<${#local_backups[@]}; i++)); do
            log "Deleting local backup: ${local_backups[i]}"
            rm "${local_backups[i]}"
        done
    else
        log "No local backups need to be deleted"
    fi

    # Clean up MEGA backups
    log "Cleaning up old backups on MEGA..."
    mega_backups=($(mega-ls /backup/ | grep ${CONTAINER} | sort -r))
    log "Found ${#mega_backups[@]} backups on MEGA"
    
    if [ ${#mega_backups[@]} -gt $MEGA_BACKUP_COUNT ]; then
        log "Keeping $MEGA_BACKUP_COUNT most recent backups on MEGA"
        for ((i=$MEGA_BACKUP_COUNT; i<${#mega_backups[@]}; i++)); do
            log "Deleting MEGA backup: /backup/${mega_backups[i]}"
            if mega-rm "/backup/${mega_backups[i]}"; then
                log "Successfully deleted MEGA backup: ${mega_backups[i]}"
            else
                log "Failed to delete MEGA backup: ${mega_backups[i]}"
            fi
        done
    else
        log "No MEGA backups need to be deleted"
    fi
}

cleanup_old_snapshots
cleanup_old_files
create_and_upload_snapshot
cleanup_old_backups

log "Backup process completed."

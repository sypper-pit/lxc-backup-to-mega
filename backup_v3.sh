#!/bin/bash
set -e

trap 'echo "Error occurred in line $LINENO. Exiting..."; exit 1' ERR

CONTAINER="container-name"
ARCHIVE=0  # 0 = no compression, 1-9 = xz levels
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
mkdir -p "${SCRIPT_DIR}/backup"

if ! mega-ls / | grep -q '^backup$'; then
    log "Creating backup folder on MEGA..."
    mega-mkdir /backup || { log "Error creating MEGA folder"; exit 1; }
fi

cleanup_old_snapshots() {
    log "Cleaning up old snapshots..."
    local snapshots=($(lxc info $CONTAINER | sed -n '/Snapshots:/,/^$/p' | grep '|' | awk -F'|' '{print $2}' | awk '{$1=$1};1' | grep -v '^NAME'))
    if [ ${#snapshots[@]} -gt $SNAPSHOT_COUNT ]; then
        to_delete=$(( ${#snapshots[@]} - $SNAPSHOT_COUNT ))
        log "Deleting $to_delete old snapshots"
        for ((i=0; i<$to_delete; i++)); do
            log "Deleting snapshot: ${snapshots[i]}"
            lxc delete "$CONTAINER/${snapshots[i]}"
        done
    fi
}

cleanup_old_files() {
    log "Cleaning up old files in $TMP_DIR..."
    find "$TMP_DIR" -name "${CONTAINER}-*.tar.gz*" -type f -delete
}

create_and_upload_snapshot() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local archive_base="${CONTAINER}-${timestamp}.tar.gz"
    local archive_path="${TMP_DIR}/${archive_base}"
    local final_file="$archive_base"

    log "Creating snapshot for $CONTAINER..."
    lxc snapshot $CONTAINER "snap-${timestamp}"

    log "Exporting snapshot to $archive_path..."
    lxc export "${CONTAINER}" "$archive_path" --instance-only

    if [ $ARCHIVE -gt 0 ]; then
        log "Compressing $archive_path with xz -$ARCHIVE..."
        xz -$ARCHIVE -T0 "$archive_path"
        final_file="${archive_base}.xz"
        log "Compression finished: ${final_file}"
    else
        log "Compression skipped."
    fi

    log "Uploading $final_file to MEGA..."
    mega-put "${TMP_DIR}/${final_file}" /backup/
}

cleanup_old_backups() {
    log "Moving files from ${TMP_DIR} to ${SCRIPT_DIR}/backup"
    mv "${TMP_DIR}"/${CONTAINER}-*.tar.gz* "${SCRIPT_DIR}/backup/" 2>/dev/null || true

    log "Cleaning up local backups in ${SCRIPT_DIR}/backup"
    local_backups=($(find "${SCRIPT_DIR}/backup" -name "${CONTAINER}-*.tar.gz*" -type f -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-))
    if [ ${#local_backups[@]} -gt $LOCAL_BACKUP_COUNT ]; then
        log "Keeping $LOCAL_BACKUP_COUNT most recent local backups"
        for ((i=$LOCAL_BACKUP_COUNT; i<${#local_backups[@]}; i++)); do
            log "Deleting local backup: ${local_backups[i]}"
            rm "${local_backups[i]}"
        done
    else
        log "No local backups need to be deleted"
    fi

    log "Cleaning up old backups on MEGA..."
    mega_backups=($(mega-ls /backup/ | grep ${CONTAINER} | sort -r))
    if [ ${#mega_backups[@]} -gt $MEGA_BACKUP_COUNT ]; then
        log "Keeping $MEGA_BACKUP_COUNT most recent backups on MEGA"
        for ((i=$MEGA_BACKUP_COUNT; i<${#mega_backups[@]}; i++)); do
            log "Deleting MEGA backup: /backup/${mega_backups[i]}"
            mega-rm "/backup/${mega_backups[i]}"
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

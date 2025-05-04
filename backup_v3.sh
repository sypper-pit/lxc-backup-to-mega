#!/bin/bash
set -e

trap 'echo "Error occurred in line $LINENO. Exiting..."; exit 1' ERR

# Configuration
CONTAINER="container-name"
ARCHIVE=3  # 0 = no compression, 1-9 = xz levels
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

# Dependency checks
for cmd in lxc xz mega-put mega-ls mega-mkdir; do
    if ! command -v $cmd &> /dev/null; then
        log "Error: $cmd is not installed or not in PATH"
        exit 1
    fi
done

# Container existence check
if ! lxc info $CONTAINER &>/dev/null; then
    log "Container $CONTAINER does not exist"
    exit 1
fi

mkdir -p "$TMP_DIR"

# Mega.nz folder setup
if ! mega-ls / | grep -q '^backup$'; then
    log "Creating backup folder on MEGA..."
    mega-mkdir /backup || { log "Error creating MEGA folder"; exit 1; }
fi

cleanup_old_snapshots() {
    log "Cleaning snapshots..."
    local snapshots=($(lxc ls $CONTAINER --format json | jq -r '.[].snapshots[].name'))
    
    if [ ${#snapshots[@]} -gt $SNAPSHOT_COUNT ]; then
        to_delete=$(( ${#snapshots[@]} - $SNAPSHOT_COUNT ))
        log "Removing $to_delete old snapshots"
        for ((i=0; i<$to_delete; i++)); do
            lxc delete "$CONTAINER/${snapshots[i]}"
        done
    fi
}

create_and_upload_snapshot() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local snapshot_name="snap-${timestamp}"
    local archive_base="${CONTAINER}-${timestamp}.tar.gz"
    local final_file=""

    # Create snapshot
    log "Creating snapshot: $snapshot_name"
    lxc snapshot $CONTAINER "${snapshot_name}"

    # Export container
    log "Exporting to ${TMP_DIR}/${archive_base}"
    lxc export "${CONTAINER}" "${TMP_DIR}/${archive_base}" --instance-only

    # Compression handling
    if [ $ARCHIVE -gt 0 ]; then
        log "Compressing with xz level $ARCHIVE..."
        if xz -${ARCHIVE} -T0 "${TMP_DIR}/${archive_base}"; then
            final_file="${archive_base}.xz"
            log "Compression completed: ${final_file}"
        else
            log "Compression failed. Using uncompressed file"
            final_file="${archive_base}"
        fi
    else
        log "Skipping compression"
        final_file="${archive_base}"
    fi

    # Upload to MEGA
    log "Uploading ${final_file} to MEGA..."
    mega-put "${TMP_DIR}/${final_file}" /backup/
}

cleanup_old_files() {
    log "Cleaning temporary files..."
    find "$TMP_DIR" -name "${CONTAINER}-*.tar.gz*" -mtime +1 -delete
}

cleanup_old_backups() {
    # Local backups
    local local_files=($(find "${SCRIPT_DIR}/backup" -name "${CONTAINER}-*.tar.gz*" -printf '%T@ %p\n' | 
                        sort -nr | cut -d' ' -f2-))
    if [ ${#local_files[@]} -gt $LOCAL_BACKUP_COUNT ]; then
        log "Removing $(( ${#local_files[@]} - $LOCAL_BACKUP_COUNT )) local backups"
        for ((i=LOCAL_BACKUP_COUNT; i<${#local_files[@]}; i++)); do
            rm "${local_files[i]}"
        done
    fi

    # MEGA backups
    local mega_files=($(mega-ls /backup/ | grep ${CONTAINER} | sort -r))
    if [ ${#mega_files[@]} -gt $MEGA_BACKUP_COUNT ]; then
        log "Removing $(( ${#mega_files[@]} - $MEGA_BACKUP_COUNT )) MEGA backups"
        for ((i=MEGA_BACKUP_COUNT; i<${#mega_files[@]}; i++)); do
            mega-rm "/backup/${mega_files[i]}"
        done
    fi
}

# Main execution
cleanup_old_snapshots
cleanup_old_files
create_and_upload_snapshot
cleanup_old_backups

log "Backup process completed successfully"

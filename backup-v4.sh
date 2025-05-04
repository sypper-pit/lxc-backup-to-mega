#!/bin/bash
set -e

trap 'echo "Error occurred in line $LINENO. Exiting..."; exit 1' ERR

# CONFIGURATION
CONTAINER="container-name"
ARCHIVE=0              # 0 = no compression, 1-9 = xz compression level
LOCAL_BACKUP_COUNT=2
MEGA_BACKUP_COUNT=0    # 0 = disable all MEGA actions, >0 = keep N latest backups on MEGA
SNAPSHOT_COUNT=2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="${SCRIPT_DIR}/tmp"
BACKUP_DIR="${SCRIPT_DIR}/backup"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting backup process for container: $CONTAINER"
log "LXC version: $(lxc --version)"
log "Container status:"
lxc info $CONTAINER | grep Status

# Check dependencies
for cmd in lxc xz; do
    if ! command -v $cmd &> /dev/null; then
        log "Error: $cmd is not installed or not in PATH"
        exit 1
    fi
done

if [ "$MEGA_BACKUP_COUNT" -gt 0 ]; then
    for cmd in mega-put mega-ls mega-mkdir mega-rm; do
        if ! command -v $cmd &> /dev/null; then
            log "Error: $cmd is not installed or not in PATH"
            exit 1
        fi
    done
fi

# Check container existence
if ! lxc info $CONTAINER &>/dev/null; then
    log "Container $CONTAINER does not exist"
    exit 1
fi

mkdir -p "$TMP_DIR"
mkdir -p "$BACKUP_DIR"

# MEGA folder setup (if enabled)
if [ "$MEGA_BACKUP_COUNT" -gt 0 ]; then
    if ! mega-ls / | grep -q '^backup$'; then
        log "Creating backup folder on MEGA..."
        mega-mkdir /backup || { log "Error creating MEGA folder"; exit 1; }
    fi
fi

cleanup_old_snapshots() {
    log "Cleaning up old snapshots..."
    local snapshots=($(lxc info $CONTAINER | sed -n '/Snapshots:/,/^$/p' | grep '|' | awk -F'|' '{print $2}' | awk '{$1=$1};1' | grep -v '^NAME'))
    if [ ${#snapshots[@]} -gt $SNAPSHOT_COUNT ]; then
        local to_delete=$(( ${#snapshots[@]} - $SNAPSHOT_COUNT ))
        log "Deleting $to_delete old snapshots"
        for ((i=0; i<$to_delete; i++)); do
            log "Deleting snapshot: ${snapshots[i]}"
            lxc delete "$CONTAINER/${snapshots[i]}"
        done
    else
        log "No old snapshots to delete."
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
        log "Compressing $archive_path with xz -$ARCHIVE (this may take a while)..."
        xz -$ARCHIVE -T0 "$archive_path"
        final_file="${archive_base}.xz"
        log "Compression finished: ${final_file}"
    else
        log "Compression skipped."
    fi

    if [ "$MEGA_BACKUP_COUNT" -gt 0 ]; then
        log "Uploading $final_file to MEGA..."
        mega-put "${TMP_DIR}/${final_file}" /backup/
        log "Upload to MEGA completed."
    else
        log "MEGA upload skipped (MEGA_BACKUP_COUNT=0)"
    fi
}

cleanup_old_backups() {
    log "Moving files from $TMP_DIR to $BACKUP_DIR"
    mv "${TMP_DIR}"/${CONTAINER}-*.tar.gz* "$BACKUP_DIR/" 2>/dev/null || true

    log "Cleaning up local backups in $BACKUP_DIR"
    local local_backups=($(find "$BACKUP_DIR" -name "${CONTAINER}-*.tar.gz*" -type f -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-))
    if [ ${#local_backups[@]} -gt $LOCAL_BACKUP_COUNT ]; then
        log "Keeping $LOCAL_BACKUP_COUNT most recent local backups"
        for ((i=$LOCAL_BACKUP_COUNT; i<${#local_backups[@]}; i++)); do
            log "Deleting local backup: ${local_backups[i]}"
            rm "${local_backups[i]}"
        done
    else
        log "No local backups need to be deleted"
    fi

    if [ "$MEGA_BACKUP_COUNT" -gt 0 ]; then
        log "Cleaning up old backups on MEGA..."
        local mega_backups=($(mega-ls /backup/ | grep ${CONTAINER} | sort -r))
        if [ ${#mega_backups[@]} -gt $MEGA_BACKUP_COUNT ]; then
            log "Keeping $MEGA_BACKUP_COUNT most recent backups on MEGA"
            for ((i=$MEGA_BACKUP_COUNT; i<${#mega_backups[@]}; i++)); do
                log "Deleting MEGA backup: /backup/${mega_backups[i]}"
                mega-rm "/backup/${mega_backups[i]}"
            done
        else
            log "No MEGA backups need to be deleted"
        fi
    else
        log "MEGA cleanup skipped (MEGA_BACKUP_COUNT=0)"
    fi
}

# MAIN EXECUTION
cleanup_old_snapshots
cleanup_old_files
create_and_upload_snapshot
cleanup_old_backups

log "Backup process completed."

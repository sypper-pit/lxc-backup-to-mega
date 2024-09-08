#!/bin/bash
set -e

trap 'echo "Error occurred in line $LINENO. Exiting..."; exit 1' ERR

CONTAINER="lcx-container-name"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backup"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

install_dependencies() {
    log "Installing dependencies..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y lxc xz-utils
    elif command -v yum &> /dev/null; then
        sudo yum install -y epel-release
        sudo yum install -y lxc xz
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y lxc xz
    elif command -v pacman &> /dev/null; then
        sudo pacman -Sy lxc xz
    else
        log "Unsupported package manager. Please install LXC and XZ manually."
        exit 1
    fi
}

restore_container() {
    log "Restoring container..."
    
    local backups=($(find "$BACKUP_DIR" -name "${CONTAINER}-*.tar.gz.xz" -type f -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-))
    
    if [ ${#backups[@]} -eq 0 ]; then
        log "No backups found for restoration."
        exit 1
    fi

    echo "Available backups:"
    for i in "${!backups[@]}"; do
        echo "$((i+1)). $(basename "${backups[$i]}")"
    done

    read -p "Enter the number of the backup you want to restore: " choice
    choice=$((choice-1))

    if [ $choice -lt 0 ] || [ $choice -ge ${#backups[@]} ]; then
        log "Invalid choice. Exiting..."
        exit 1
    fi

    local selected_backup="${backups[$choice]}"
    local extracted_backup="${selected_backup%.xz}"

    log "Uncompressing selected backup..."
    xz -d "$selected_backup"

    log "Stopping existing container if running..."
    lxc stop "$CONTAINER" || true

    log "Deleting existing container..."
    lxc delete "$CONTAINER" || true

    log "Importing container from backup..."
    lxc import "$extracted_backup" "$CONTAINER"

    log "Starting restored container..."
    lxc start "$CONTAINER"

    log "Cleaning up..."
    rm "$extracted_backup"
    xz "$extracted_backup"

    log "Container restored successfully."
}

# Main execution
install_dependencies
restore_container

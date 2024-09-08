#!/bin/bash
set -e

trap 'echo "Error occurred in line $LINENO. Exiting..."; exit 1' ERR

CONTAINER="lcx-container-name"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="${SCRIPT_DIR}/tmp"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting restore process for container: $CONTAINER"

if ! lxc info $CONTAINER &>/dev/null; then
    log "Container $CONTAINER does not exist. Creating a new container..."
    lxc init $CONTAINER ubuntu
fi

if ! command -v lxc &> /dev/null; then
    log "Error: lxc is not installed or not in PATH"
    exit 1
fi

if ! command -v xz &> /dev/null; then
    log "Error: xz is not installed or not in PATH"
    exit 1
fi

mkdir -p "$TMP_DIR"

# Define the path to the backup directory
BACKUP_DIR="${SCRIPT_DIR

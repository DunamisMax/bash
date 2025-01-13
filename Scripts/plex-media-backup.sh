#!/bin/bash

# --------------------------------------
# CONFIGURATION
# --------------------------------------

# Exit immediately if a command exits with a non-zero status,
# if any variable is unset, and if any command in a pipeline fails
set -euo pipefail

# Variables
BACKUP_SOURCE="/mnt/media/WD_BLACK/"
BACKUP_DEST="Backblaze:plex-sawyer"
LOG_FILE="/var/log/backblaze-backup.log"
RCLONE_CONFIG="/home/sawyer/.config/rclone/rclone.conf"
RETENTION_DAYS=30

# --------------------------------------
# FUNCTIONS
# --------------------------------------

# Function to log messages with timestamp
log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOG_FILE"
}

# Function to synchronize the source directory to Backblaze B2
sync_backup() {
    log "Starting synchronization of $BACKUP_SOURCE to $BACKUP_DEST"
    /usr/bin/rclone --config "$RCLONE_CONFIG" sync "$BACKUP_SOURCE" "$BACKUP_DEST" -vv >> "$LOG_FILE" 2>&1
    log "Synchronization completed successfully."
}

# Function to remove old backups from Backblaze B2
cleanup_backups() {
    log "Removing old backups (older than ${RETENTION_DAYS} days) from Backblaze B2: $BACKUP_DEST"
    /usr/bin/rclone --config "$RCLONE_CONFIG" delete "$BACKUP_DEST" --min-age "${RETENTION_DAYS}d" -vv >> "$LOG_FILE" 2>&1
    log "Old backups removed successfully."
}

# Function to handle errors
handle_error() {
    log "An error occurred during the backup process. Check the log for details."
    exit 1
}

# Trap errors and execute handle_error
trap 'handle_error' ERR

# --------------------------------------
# SCRIPT START
# --------------------------------------

# Ensure the log file exists and has appropriate permissions
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log "--------------------------------------"
log "Starting Backblaze B2 Backup Script"

# Step 1: Synchronize the source directory to Backblaze B2
sync_backup

# Step 2: Remove backups older than RETENTION_DAYS days from Backblaze B2
cleanup_backups

log "Backup and cleanup completed successfully on $(date)."
log "--------------------------------------"

exit 0

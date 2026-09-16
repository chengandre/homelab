#!/bin/bash

IMMICH_DIR="/mnt/truenas/immich/library/upload"
TO_PROCESS_DIR="/mnt/truenas/immich/pipeline/to_process"
STAGING_DIR="/mnt/truenas/immich/pipeline/staging"
LEDGER_FILE="/home/<USERNAME>/pipeline/pipeline_ledger.txt"
LOG_FILE="/home/<USERNAME>/pipeline/pipeline.log"
MOTIONPHOTO_BIN="/home/<USERNAME>/pipeline/.venv/bin/python3 /home/<USERNAME>/pipeline/MotionPhoto2/motionphoto2.py"

exec > >(tee -a "$LOG_FILE") 2>&1
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

log "=== Starting Immich Motion Photo Pipeline ==="

if [ ! -d "$IMMICH_DIR" ] || [ -z "$(ls -A "$IMMICH_DIR")" ]; then
    log "CRITICAL ERROR: TrueNAS mount is missing or empty. Aborting."
    exit 1
fi

touch "$LEDGER_FILE"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"; log "Pipeline closed. Cleaned up temp files."' EXIT

log "Scanning Immich for files..."
find "$IMMICH_DIR" -type f ! -iname "*.xmp" ! -iname "*.immich" > "$TEMP_DIR/immich_all_paths.txt"
awk -F/ '{print $NF}' "$TEMP_DIR/immich_all_paths.txt" | sort > "$TEMP_DIR/immich_basenames.txt"
sort "$LEDGER_FILE" > "$TEMP_DIR/ledger_sorted.txt"

comm -23 "$TEMP_DIR/immich_basenames.txt" "$TEMP_DIR/ledger_sorted.txt" > "$TEMP_DIR/new_basenames.txt"
NEW_FILE_COUNT=$(wc -l < "$TEMP_DIR/new_basenames.txt")
log "Found $NEW_FILE_COUNT new files."

if [ "$NEW_FILE_COUNT" -gt 0 ]; then
    log "Hardlinking files to the sandbox..."
    awk -F/ 'NR==FNR{a[$0]; next} $NF in a' "$TEMP_DIR/new_basenames.txt" "$TEMP_DIR/immich_all_paths.txt" > "$TEMP_DIR/new_full_paths.txt"

    while IFS= read -r full_path; do
        filename=$(basename "$full_path")
        ln "$full_path" "$TO_PROCESS_DIR/$filename"
        echo "$filename" >> "$LEDGER_FILE"
    done < "$TEMP_DIR/new_full_paths.txt"

    log "Running MotionPhoto2..."
    $MOTIONPHOTO_BIN --input-directory "$TO_PROCESS_DIR" \
                     --output-directory "$STAGING_DIR" \
                     --exif-match \
                     --copy-unmuxed

    log "Cleaning To-Process folder..."
    rm -rf "${TO_PROCESS_DIR:?}/"*

    log "Pipeline completed successfully."
else
    log "Nothing to do. Pipeline finished."
fi

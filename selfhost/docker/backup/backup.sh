#!/bin/sh
# Daily mongodump, run in the mongo image by quantaid-backup.timer
set -e

BACKUP_DIR=/backups
RETENTION_DAYS=14
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEST="$BACKUP_DIR/$TIMESTAMP"

# A config file keeps the Atlas credential out of the process list
printf 'uri: %s\n' "$MONGODB_BACKUP_URI" > /tmp/mongodump-config.yaml

mkdir -p "$DEST"
mongodump --config=/tmp/mongodump-config.yaml --gzip --out="$DEST"

find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

echo "quantaid_backup_last_success_timestamp $(date +%s)" > /textfile/quantaid_backup.prom.tmp
mv /textfile/quantaid_backup.prom.tmp /textfile/quantaid_backup.prom

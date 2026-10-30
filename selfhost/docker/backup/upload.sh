#!/bin/sh
# Copies the newest local dump to Azure Blob storage, then pings this host's backup heartbeat.
# Run on the host by quantaid-backup.service after the dump, as root: the dumps are root-only.
set -e

cd "$(dirname "$0")/.."

BACKUPS=/var/backups/quantaid-mongo
SAS_URL=$(sed -n 's/^BACKUP_SAS_URL=//p' host.env)
HC_PING_KEY=$(sed -n 's/^HC_PING_KEY=//p' host.env)
SERVED_BY=$(sed -n 's/^SERVED_BY=//p' host.env)
: "${SAS_URL:?missing from host.env}" "${HC_PING_KEY:?missing from host.env}" "${SERVED_BY:?missing from host.env}"

# backup.sh names each dump's folder by its time, so the newest sorts last
newest=$(find "$BACKUPS" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n 1)
archive=$(mktemp)
trap 'rm -f "$archive"' EXIT
# Plain tar: mongodump already gzipped each file
tar -cf "$archive" -C "$BACKUPS" "$newest"

# The SAS can create and write blobs, but not read, list or delete them, and the container keeps every blob for
# 14 days. So a host that leaks it can't destroy the backups.
curl -fsS --retry 3 -T "$archive" -H "x-ms-blob-type: BlockBlob" "${SAS_URL%%\?*}/$SERVED_BY/$newest.tar?${SAS_URL#*\?}"
echo "Uploaded $newest"

# Healthchecks.io alerts when this stops for a day: this host's backups aren't leaving it
curl -fsS -m 10 --retry 3 -o /dev/null "https://hc-ping.com/$HC_PING_KEY/backup-$SERVED_BY"

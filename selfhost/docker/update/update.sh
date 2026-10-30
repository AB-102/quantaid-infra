#!/bin/sh
# Deploys the release that selfhost/release.env pins on main. Run every 5 minutes by quantaid-update.timer, as anb.
#
# Prepare, then switch:
#   1. Prepare: as soon as a new release appears, pull its images and add its /assets/ files to the shared assets
#      folder the frontend serves. Nothing serves the release yet.
#   2. Switch: SWITCH_DELAY_MINUTES after the release.env change reached main. By then every running host has the
#      release's files, so a page from either release finds every file it needs on any host.
#   3. Clean: delete asset files that no release from the last 30 days uses.
# .env is this script's output: host.env (this host's settings and secrets) plus release.env.
set -e

cd "$(dirname "$0")/.."

ASSETS=/var/lib/quantaid/assets
MANIFESTS=/var/lib/quantaid/manifests
WORK=/var/lib/quantaid
BACKEND_IMAGE=ghcr.io/ab-102/quantaid-backend
FRONTEND_IMAGE=ghcr.io/ab-102/quantaid-frontend
# Tells the health gate (gate/gate.sh) this host may join the tunnel. In quantaid-update.service's RuntimeDirectory,
# so a reboot clears it until this script's first run.
RELEASE_OK=/run/quantaid/release-ok

HC_PING_KEY=$(sed -n 's/^HC_PING_KEY=//p' host.env)
SERVED_BY=$(sed -n 's/^SERVED_BY=//p' host.env)
: "${HC_PING_KEY:?missing from host.env}" "${SERVED_BY:?missing from host.env}"

# Written again below once this run knows. A failed run leaves it missing.
rm -f "$RELEASE_OK"

# Only release.env is read from main; other infra changes still wait for a manual git pull
git fetch --quiet origin main
git show origin/main:selfhost/release.env > desired-release.env
# When the release.env change reached main. git log's path is relative to this folder, unlike git show's.
MERGED_AT=$(git log -1 --format=%ct origin/main -- ../release.env)
# shellcheck source=/dev/null
. ./desired-release.env
: "${MERGED_AT:?}" "${QUANTAID_VERSION:?missing from release.env}" "${SWITCH_DELAY_MINUTES:?missing from release.env}"

# .env holds secrets, so only anb can read it
(umask 077 && cat host.env desired-release.env > desired.env)

if [ -f .env ]; then
    DEPLOYED=$(sed -n 's/^QUANTAID_VERSION=//p' .env)
else
    DEPLOYED=
fi

# 1. Prepare. The manifest is written last, so its presence means the release's files are all in place.
if [ ! -f "$MANIFESTS/$QUANTAID_VERSION" ]; then
    echo "Preparing $QUANTAID_VERSION"
    docker compose --env-file desired.env pull --quiet
    # Their profiles can be off on this host, but the gate and the backup timer need their images
    docker compose --env-file desired.env --profile tunnel --profile backup pull --quiet cloudflared backup
    tmp=$(mktemp -d "$WORK/prepare.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    container=$(docker create "$FRONTEND_IMAGE:$QUANTAID_VERSION")
    docker cp "$container:/usr/share/nginx/html/assets" "$tmp/"
    docker rm "$container" > /dev/null
    (cd "$tmp/assets" && find . -type f) > "$tmp/manifest"
    # Only files the folder doesn't have yet: a file name includes a hash of its contents, so an existing name
    # already has the right contents, and rewriting a file nginx may be serving could hand out a half-written copy.
    # Plain cp, not cp -a: the copies must take the folder's SELinux label, which the frontend container can read.
    while read -r file; do
        if [ ! -e "$ASSETS/$file" ]; then
            mkdir -p "$ASSETS/$(dirname "$file")"
            cp "$tmp/assets/$file" "$ASSETS/$file"
        fi
    done < "$tmp/manifest"
    mv "$tmp/manifest" "$MANIFESTS/$QUANTAID_VERSION"
fi

# 2. Switch
SWITCH_AT=$((MERGED_AT + SWITCH_DELAY_MINUTES * 60))
if cmp -s desired.env .env; then
    rm desired.env
elif [ "$DEPLOYED" != "$QUANTAID_VERSION" ] && [ "$(date +%s)" -lt "$SWITCH_AT" ]; then
    echo "$QUANTAID_VERSION is prepared; switching after $(date -d "@$SWITCH_AT" '+%H:%M:%S')"
else
    # Either a new release whose switch time has come, or only host.env changed, which applies right away
    echo "Deploying $QUANTAID_VERSION"
    # The gate takes the same lock, so it never starts or stops cloudflared in the middle of a deploy
    exec 9> "$WORK/deploy.lock"
    flock 9
    mv desired.env .env
    if systemctl is-active --quiet quantaid-gate && [ -n "$(docker compose --profile tunnel ps --quiet --status running cloudflared)" ]; then
        # Drain: a stopped cloudflared takes no new requests and finishes the ones in flight, so users go to the
        # other hosts while this one restarts. Without the gate, this host may be the only one serving.
        echo "Draining this host's tunnel connector"
        docker compose --profile tunnel stop cloudflared
        docker compose up -d --wait --wait-timeout 180
        docker compose --profile tunnel up -d cloudflared
    else
        docker compose up -d --wait --wait-timeout 180
    fi
    flock -u 9
    if [ -n "$DEPLOYED" ] && [ "$DEPLOYED" != "$QUANTAID_VERSION" ]; then
        # A rollback pulls it again; || true in case it was already removed by hand
        docker image rm "$BACKEND_IMAGE:$DEPLOYED" "$FRONTEND_IMAGE:$DEPLOYED" > /dev/null || true
    fi
    docker image prune -f > /dev/null
    DEPLOYED=$QUANTAID_VERSION
fi

# This host is current if it runs the desired release, or the desired release's switch time hasn't come yet
if [ "$DEPLOYED" = "$QUANTAID_VERSION" ] || [ "$(date +%s)" -lt "$SWITCH_AT" ]; then
    touch "$RELEASE_OK"
    # Healthchecks.io alerts when this stops for an hour: this host keeps failing to update
    curl -fsS -m 10 --retry 3 -o /dev/null "https://hc-ping.com/$HC_PING_KEY/update-$SERVED_BY" || echo "Heartbeat ping failed"
fi

# 3. Clean. By the manifests' dates, not the files': docker cp keeps each file's build date, so an unchanged
# welcome.mp4 looks months old while still in use. The deployed and desired releases are always kept.
find "$MANIFESTS" -type f -mtime +30 ! -name "$QUANTAID_VERSION" ! -name "$DEPLOYED" -delete
cat "$MANIFESTS"/* | sort -u > "$WORK/used-assets"
(cd "$ASSETS" && find . -type f) | sort > "$WORK/present-assets"
comm -23 "$WORK/present-assets" "$WORK/used-assets" | (cd "$ASSETS" && xargs -r -d '\n' rm -f)
rm "$WORK/used-assets" "$WORK/present-assets"

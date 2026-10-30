#!/bin/sh
# Health gate: keeps this host in the Cloudflare Tunnel only while its app answers. Run by quantaid-gate.service,
# as anb. Every host is a connector of the one tunnel, and Cloudflare splits traffic between the connected ones.
#
# Every 15 s it checks /api/health through this host's own proxy, which tests nginx and the backend together.
#   - 3 failures in a row (about 45 s) stop this host's cloudflared, so users go to the other hosts.
#   - 2 passes in a row start it again, once this host runs the current release (the updater writes release-ok).
#     After 15 minutes of waiting for that, it joins on the release it has, so a GHCR outage can't keep every host
#     out; the updater's heartbeat alerts instead.
# It only needs the app to answer, not the database: with Atlas down, every host would leave, and users would get
# Cloudflare's error page instead of the app. A database error raises an alert instead.
# While in the tunnel and passing, it pings this host's heartbeat about once a minute.
set -u

cd "$(dirname "$0")/.." || exit

RELEASE_OK=/run/quantaid/release-ok
HC_PING_KEY=$(sed -n 's/^HC_PING_KEY=//p' host.env)
SERVED_BY=$(sed -n 's/^SERVED_BY=//p' host.env)
: "${HC_PING_KEY:?missing from host.env}" "${SERVED_BY:?missing from host.env}"

# Shared with the updater, so the gate never starts or stops cloudflared in the middle of a deploy
exec 9> /var/lib/quantaid/deploy.lock

passes=0
fails=0
checks=0
waiting_since=

while true; do
    flock 9

    if curl -fs -m 5 -o /dev/null http://127.0.0.1/api/health; then
        passes=$((passes + 1))
        fails=0
    else
        fails=$((fails + 1))
        passes=0
    fi
    checks=$((checks + 1))

    if [ -n "$(docker compose --profile tunnel ps --quiet --status running cloudflared)" ]; then
        in_tunnel=yes
        waiting_since=
        if [ "$fails" -ge 3 ]; then
            echo "The app failed 3 checks in a row; leaving the tunnel"
            docker compose --profile tunnel stop cloudflared
            in_tunnel=no
        fi
    else
        in_tunnel=no
        if [ "$passes" -ge 2 ]; then
            if [ -f "$RELEASE_OK" ]; then
                echo "The app passes; joining the tunnel"
                docker compose --profile tunnel up -d cloudflared
                in_tunnel=yes
            elif [ -z "$waiting_since" ]; then
                echo "The app passes, but this host isn't on the current release; waiting for the updater"
                waiting_since=$(date +%s)
            elif [ $(($(date +%s) - waiting_since)) -ge 900 ]; then
                echo "Still not on the current release after 15 minutes; joining on the release it has"
                docker compose --profile tunnel up -d cloudflared
                in_tunnel=yes
                waiting_since=
            fi
        fi
    fi

    flock -u 9

    if [ "$in_tunnel" = yes ] && [ "$passes" -gt 0 ] && [ $((checks % 4)) -eq 0 ]; then
        # Healthchecks.io alerts when this stops for 5 minutes: this host is down or out of the tunnel
        curl -fsS -m 10 -o /dev/null "https://hc-ping.com/$HC_PING_KEY/host-$SERVED_BY" || echo "Heartbeat ping failed"
    fi

    sleep 15
done

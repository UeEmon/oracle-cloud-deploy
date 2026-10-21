#!/bin/sh
# Back up the data of every system to Object Storage. Run daily by systemd/chuck-backup.timer.
# Secrets (.env, env/*.env) are not included; the owner keeps copies on the Mac.
set -eu
cd "$(dirname "$0")/.."
value() { sed -n "s/^$1=//p" .env | tail -1 | sed "s/^['\"]//;s/['\"]\$//"; }
BACKUP_BUCKET=$(value BACKUP_BUCKET)
BACKUP_KEEP_DAYS=$(value BACKUP_KEEP_DAYS)
export BACKUP_BUCKET BACKUP_KEEP_DAYS
out=$(mktemp -d)
# The upload container runs as nobody and must read this folder.
chmod 755 "$out"
trap 'rm -rf "$out"' EXIT
project=$(docker compose config --format json | python3 -c "import json,sys;print(json.load(sys.stdin)['name'])")
# PostgreSQL: a consistent dump from the running database.
docker compose exec -T db pg_dump -U arn --format=custom arn > "$out/arn.pgdump"
docker compose -p enmea exec -T db pg_dump -U nmea --format=custom nmea > "$out/enmea.pgdump"
# Everything else: one archive per volume (Caddy's certificates are left out; they are issued again).
snapshot() {
	docker run --rm -v "$1:/src" -v "$PWD/backup/snapshot.py:/snapshot.py:ro" python:3.12-slim python -I /snapshot.py /src > "$out/$2.tar.gz"
}
for volume in hf-data gateway-data artifacts hacs_data bacchus-data; do snapshot "${project}_$volume" "$volume"; done
snapshot enmea_raw-data enmea-raw-data
docker build --quiet --tag chuck-backup backup >/dev/null
docker run --rm --network host -e BACKUP_BUCKET -e BACKUP_KEEP_DAYS -v "$out:/backup:ro" chuck-backup /backup "$(date -u +%Y-%m-%dT%H%M%SZ)"

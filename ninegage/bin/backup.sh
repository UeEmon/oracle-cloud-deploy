#!/bin/sh
# Back up production's data, encrypted by the app (NINEGAGE_BACKUP_KEY), to Object Storage under <BACKUP_PREFIX>/<time>/.
# Run daily by systemd/ninegage-backup.timer. Staging is not backed up. Uses ../backup (the VM's instance principal).
set -eu
cd "$(dirname "$0")/.."
value() { sed -n "s/^$1=//p" .env | tail -1 | sed "s/^['\"]//;s/['\"]\$//"; }
BACKUP_BUCKET=$(value BACKUP_BUCKET)
BACKUP_KEEP_DAYS=$(value BACKUP_KEEP_DAYS)
prefix=$(value BACKUP_PREFIX)
export BACKUP_BUCKET BACKUP_KEEP_DAYS
out=$(mktemp -d)
# The upload container runs as nobody and must read this folder.
chmod 755 "$out"
trap 'rm -rf "$out"' EXIT
docker compose exec -T nine-gage node --disable-warning=ExperimentalWarning scripts/backup.mjs > "$out/ninegage.ngbak"
chmod 644 "$out/ninegage.ngbak"
[ -s "$out/ninegage.ngbak" ] || { echo "empty backup" >&2; exit 1; }
docker build --quiet --tag chuck-backup ../backup >/dev/null
docker run --rm --network host -e BACKUP_BUCKET -e BACKUP_KEEP_DAYS -v "$out:/backup:ro" chuck-backup /backup "${prefix:-ninegage}/$(date -u +%Y-%m-%dT%H%M%SZ)"

#!/bin/sh
# Start or rebuild every system: the main project, then eNMEA2000 as its own project.
set -eu
cd "$(dirname "$0")/.."
docker compose up -d --build
docker compose -p enmea --env-file env/enmea.env -f apps/eNMEA2000/compose.yaml -f overrides/enmea.yaml up -d --build
# altpnt (simulator API) is its own project too. Only its API runs here; a failed build is reported
# but does not stop the other systems from being updated.
docker compose -p altpnt --env-file env/altpnt.env -f apps/altpnt/docker-compose.yml -f overrides/altpnt.yaml up -d --build cloud \
	|| echo "WARN: altpnt did not start; the other systems are up" >&2
# The Caddyfile is a bind mount, so a new site is not picked up unless Caddy reloads.
# reload checks the new file first and keeps the running config when it is invalid.
docker compose exec -T https-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile \
	|| echo "WARN: Caddy kept its previous config" >&2

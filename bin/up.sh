#!/bin/sh
# Start or rebuild every system.
set -eu
cd "$(dirname "$0")/.."
docker compose up -d --build
# The caddy directory is a bind mount, so a new site is not picked up unless Caddy reloads.
# reload checks the new file first and keeps the running config when it is invalid.
docker compose exec -T https-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile \
	|| echo "WARN: Caddy kept its previous config" >&2

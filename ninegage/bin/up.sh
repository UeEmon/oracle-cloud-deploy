#!/bin/sh
# Start or update everything, then make Caddy read a changed Caddyfile (it keeps the old config if the new one is invalid).
set -eu
cd "$(dirname "$0")/.."
docker compose up -d --remove-orphans
docker compose exec -T https-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile \
	|| echo "WARN: Caddy kept its previous config" >&2

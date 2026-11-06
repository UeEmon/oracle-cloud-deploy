#!/bin/sh
# Refuse to start if a public app would come up with development settings.
set -eu
cd "$(dirname "$0")/.."
# Refuse an empty or unpublished OpenWeather checkout instead of serving a broken site.
for asset in index.html style.css app.js weather.mjs gis-terrain.mjs browser-settings.mjs collector-admin.html collector-admin.js areas.js vendor/cesium/Cesium.js collector/Dockerfile collector/server.py collector/additional_sources.py collector/sources.json collector/areas.json; do
 [ -s "apps/OpenWeather/$asset" ] || { echo "Missing apps/OpenWeather/$asset; publish the OpenWeather source and run bin/fetch-apps.sh" >&2; exit 1; }
done
config=$(docker compose config --format json)
check() {
	actual=$(printf '%s' "$config" | python3 -c "import json,sys;print(json.load(sys.stdin)['services']['$1']['environment'].get('$2',''))")
	[ "$actual" = "$3" ] || { echo "$1 $2 is '$actual', expected '$3'" >&2; exit 1; }
}
check app AUTH_MODE local
check app NODE_ENV production
# CHUCK must run the public edition, with an admin secret only the proxy knows.
command=$(printf '%s' "$config" | python3 -c "import json,sys;print(' '.join(json.load(sys.stdin)['services']['hf-propagation'].get('command') or []))")
[ "$command" = "python public_server.py" ] || { echo "hf-propagation command is '$command', expected 'python public_server.py'" >&2; exit 1; }
secret=$(printf '%s' "$config" | python3 -c "import json,sys;print(json.load(sys.stdin)['services']['hf-propagation']['environment'].get('CHUCK_ADMIN_SECRET',''))")
[ "${#secret}" -ge 32 ] || { echo "CHUCK_ADMIN_SECRET must be 32 or more characters" >&2; exit 1; }
# The position gateway's TCP/UDP input faces the internet: only senders with a stream key.
stream=$(printf '%s' "$config" | python3 -c "import json,sys;e=json.load(sys.stdin)['services']['position-gateway']['environment'];print(e.get('HF_GATEWAY_NMEA_STREAM',''),e.get('HF_GATEWAY_NMEA_REQUIRE_KEY',''))")
[ "${stream% *}" != 1 ] || [ "${stream#* }" = 1 ] || { echo "position-gateway HF_GATEWAY_NMEA_REQUIRE_KEY must be 1 when the TCP/UDP input is on" >&2; exit 1; }
# Its web screen and HTTP APIs stay on the VM; only the NMEA port is public.
web=$(printf '%s' "$config" | python3 -c "import json,sys;print(' '.join(str(p.get('host_ip')) for p in json.load(sys.stdin)['services']['position-gateway'].get('ports',[]) if str(p.get('target'))=='8001'))")
[ "$web" = "127.0.0.1" ] || { echo "position-gateway web port binds to '$web', expected '127.0.0.1'" >&2; exit 1; }
# The gateway simulator has no login: only Caddy (with the admin password) may reach it.
simports=$(printf '%s' "$config" | python3 -c "import json,sys;print(len(json.load(sys.stdin)['services'].get('gateway-simulator',{}).get('ports') or []))")
[ "$simports" = 0 ] || { echo "gateway-simulator must not publish ports; it is reached only through Caddy" >&2; exit 1; }
# Shared data API must stay on the internal Compose network.
oceanports=$(printf '%s' "$config" | python3 -c "import json,sys;print(len(json.load(sys.stdin)['services']['ocean-data'].get('ports') or []))")
[ "$oceanports" = 0 ] || { echo "ocean-data must not publish host ports" >&2; exit 1; }
echo "config OK"

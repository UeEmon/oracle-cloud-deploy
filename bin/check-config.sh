#!/bin/sh
# Refuse to start if a public app would come up with development settings.
set -eu
cd "$(dirname "$0")/.."
# Refuse an empty or unpublished OpenWeather checkout instead of serving a broken site.
for asset in index.html style.css app.js weather.mjs gis-terrain.mjs bathymetry-gis.mjs browser-settings.mjs collector-admin.html collector-admin.js areas.js vendor/cesium/Cesium.js collector/Dockerfile collector/server.py collector/additional_sources.py collector/bathymetry.py collector/sources.json collector/areas.json; do
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
# Nine-Gage runs the image from its CI, never a local build.
for svc in nine-gage nine-gage-staging; do
	img=$(printf '%s' "$config" | python3 -c "import json,sys;s=json.load(sys.stdin)['services']['$svc'];print('' if 'build' in s else s.get('image',''))")
	case "$img" in ghcr.io/ueemon/nine-gage-systems:?*) ;; *) echo "$svc must run ghcr.io/ueemon/nine-gage-systems:<tag> without build, got '$img'" >&2; exit 1 ;; esac
done
check nine-gage NODE_ENV production
check nine-gage NINEGAGE_DATA_DIR /data
check nine-gage-staging NODE_ENV production
check nine-gage-staging NINEGAGE_DATA_DIR /data
ngurl=$(printf '%s' "$config" | python3 -c "import json,sys;print(json.load(sys.stdin)['services']['nine-gage']['environment'].get('NINEGAGE_PUBLIC_URL',''))")
case "$ngurl" in https://nine-gage.?*) ;; *) echo "nine-gage needs NINEGAGE_PUBLIC_URL=https://nine-gage.<CHUCK_DOMAIN> for its confirmation mail" >&2; exit 1 ;; esac
# Each Nine-Gage sits only on its own network, shared with Caddy alone: not on the default network of the other apps.
nets() { printf '%s' "$config" | python3 -c "import json,sys;print(' '.join(sorted((json.load(sys.stdin)['services']['$1'].get('networks') or {'default':None}).keys())))"; }
[ "$(nets nine-gage)" = ninegage-edge ] || { echo "nine-gage must be on the ninegage-edge network only, got '$(nets nine-gage)'" >&2; exit 1; }
[ "$(nets nine-gage-staging)" = ninegage-staging-edge ] || { echo "nine-gage-staging must be on the ninegage-staging-edge network only, got '$(nets nine-gage-staging)'" >&2; exit 1; }
members=$(printf '%s' "$config" | python3 -c "import json,sys;s=json.load(sys.stdin)['services'];print(' '.join(sorted(n for n,v in s.items() if set((v.get('networks') or {'default':None}).keys()) & {'ninegage-edge','ninegage-staging-edge'})))")
[ "$members" = "https-proxy nine-gage nine-gage-staging" ] || { echo "only Caddy may share the Nine-Gage networks, found: $members" >&2; exit 1; }
# The staging site needs its password for Caddy (bin/init-secrets.sh creates it).
# (docker compose config prints each $ as $$.)
stghash=$(printf '%s' "$config" | python3 -c "import json,sys;h=json.load(sys.stdin)['services']['https-proxy']['environment'].get('NINEGAGE_STAGING_PASSWORD_HASH','');print(1 if h.replace('\$\$','\$').startswith('\$2') and len(h)>50 else 0)")
case "$stghash" in 1) ;; *) echo "env/ninegage-staging-auth.env needs NINEGAGE_STAGING_PASSWORD_HASH (a bcrypt hash; bin/init-secrets.sh creates it)" >&2; exit 1 ;; esac
ngadmin=$(printf '%s' "$config" | python3 -c "import json,sys;e=json.load(sys.stdin)['services']['nine-gage']['environment'];print(1 if e.get('NINEGAGE_ADMIN_USER') and len(e.get('NINEGAGE_ADMIN_PASSWORD',''))>=10 else 0)")
[ "$ngadmin" = 1 ] || { echo "env/ninegage.env needs NINEGAGE_ADMIN_USER and a NINEGAGE_ADMIN_PASSWORD of 10 or more characters (bin/init-secrets.sh adds them)" >&2; exit 1; }
ngkey=$(printf '%s' "$config" | python3 -c "import json,sys;e=json.load(sys.stdin)['services']['nine-gage']['environment'];print(1 if len(e.get('NINEGAGE_SECRET_KEY',''))>=32 else 0)")
[ "$ngkey" = 1 ] || { echo "env/ninegage.env needs a NINEGAGE_SECRET_KEY of 32 or more characters (bin/init-secrets.sh adds it)" >&2; exit 1; }
stgadmin=$(printf '%s' "$config" | python3 -c "import json,sys;e=json.load(sys.stdin)['services']['nine-gage-staging']['environment'];print(1 if e.get('NINEGAGE_ADMIN_USER') and len(e.get('NINEGAGE_ADMIN_PASSWORD',''))>=10 and len(e.get('NINEGAGE_SECRET_KEY',''))>=32 else 0)")
[ "$stgadmin" = 1 ] || { echo "env/ninegage-staging.env needs NINEGAGE_ADMIN_USER, NINEGAGE_ADMIN_PASSWORD and NINEGAGE_SECRET_KEY (bin/init-secrets.sh creates it)" >&2; exit 1; }
for svc in nine-gage nine-gage-staging; do
	ngports=$(printf '%s' "$config" | python3 -c "import json,sys;print(len(json.load(sys.stdin)['services']['$svc'].get('ports') or []))")
	[ "$ngports" = 0 ] || { echo "$svc must not publish host ports; it is reached only through Caddy" >&2; exit 1; }
done
echo "config OK"

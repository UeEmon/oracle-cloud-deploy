#!/bin/sh
# Refuse to start if a public app would come up with development settings.
set -eu
cd "$(dirname "$0")/.."
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
# altpnt's API has no login: it must stay on 127.0.0.1 and be reached only through Caddy.
if [ -f apps/altpnt/docker-compose.yml ]; then
	bind=$(docker compose -p altpnt --env-file env/altpnt.env -f apps/altpnt/docker-compose.yml -f overrides/altpnt.yaml config --format json \
		| python3 -c "import json,sys;print(' '.join(str(p.get('host_ip')) for p in json.load(sys.stdin)['services']['cloud'].get('ports',[])))")
	[ "$bind" = "127.0.0.1" ] || { echo "altpnt cloud ports bind to '$bind', expected '127.0.0.1'" >&2; exit 1; }
fi
echo "config OK"

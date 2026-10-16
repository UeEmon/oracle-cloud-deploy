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
echo "config OK"

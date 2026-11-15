#!/bin/sh
# Pull this repo and the images; redeploy only when something moved. Run every 5 minutes by systemd/ninegage-update.timer.
# Nothing is deployed when the settings check fails; the next run tries again.
set -eu
cd "$(dirname "$0")/.."
exec 9>.auto-update.lock
flock -n 9 || exit 0
# One function, so a pull that rewrites this file cannot change the run already in progress.
main() {
	git -C .. pull --quiet --ff-only origin main
	bin/init-secrets.sh
	docker compose pull --quiet
	state="deploy $(git -C .. rev-parse HEAD)"
	for svc in nine-gage nine-gage-staging https-proxy; do
		image=$(docker compose config --format json | python3 -c "import json,sys;print(json.load(sys.stdin)['services']['$svc']['image'])")
		state="$state $svc $(docker image inspect --format '{{.Id}}' "$image")"
	done
	[ "$state" != "$(cat .deployed 2>/dev/null)" ] || exit 0
	echo "deploying: $state"
	bin/check-config.sh
	bin/up.sh
	printf '%s\n' "$state" > .deployed
	docker image prune -f >/dev/null
	echo "deployed"
}
main

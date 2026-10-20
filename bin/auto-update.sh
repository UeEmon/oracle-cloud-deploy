#!/bin/sh
# Pull this repo and the apps; rebuild only when something new was merged. Run by systemd/chuck-update.timer.
# Nothing is deployed when the settings check fails; the next run tries again.
set -eu
cd "$(dirname "$0")/.."
exec 9>.auto-update.lock
flock -n 9 || exit 0
# The whole body is one function, so a pull that rewrites this file cannot change the run already in progress.
main() {
	git pull --quiet --ff-only origin main
	bin/fetch-apps.sh
	# 要件ナビ runs the image its CI publishes, so a merge there shows up as a new image, not new source.
	docker compose pull --quiet app
	state="deploy $(git rev-parse HEAD)"
	for app in apps/*/; do state="$state $(basename "$app") $(git -C "$app" rev-parse HEAD)"; done
	state="$state app-image $(docker image inspect --format '{{.Id}}' "$(docker compose config --format json | python3 -c "import json,sys;print(json.load(sys.stdin)['services']['app']['image'])")")"
	[ "$state" != "$(cat .deployed 2>/dev/null)" ] || exit 0
	echo "deploying: $state"
	bin/check-config.sh
	docker compose up -d --build
	printf '%s\n' "$state" > .deployed
	docker image prune -f >/dev/null
	echo "deployed"
}
main

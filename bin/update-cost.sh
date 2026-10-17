#!/bin/sh
# Send this month's Oracle bill to CHUCK's donation meter. Run daily by systemd/chuck-cost.timer.
set -eu
cd "$(dirname "$0")/.."
# Read single values from .env without sourcing it (the password hash contains $).
value() { sed -n "s/^$1=//p" .env | tail -1 | sed "s/^['\"]//;s/['\"]\$//"; }
CHUCK_ADMIN_SECRET=$(value CHUCK_ADMIN_SECRET)
CHUCK_JPY_PER_USD=$(value CHUCK_JPY_PER_USD)
CHUCK_COST_URL=http://127.0.0.1:$(value HF_PORT | grep . || echo 18082)
export CHUCK_ADMIN_SECRET CHUCK_JPY_PER_USD CHUCK_COST_URL
docker build --quiet --tag chuck-cost cost >/dev/null
# Host networking reaches the app on 127.0.0.1 and the instance metadata service; the secret stays off the command line.
exec docker run --rm --network host -e CHUCK_ADMIN_SECRET -e CHUCK_JPY_PER_USD -e CHUCK_COST_URL chuck-cost

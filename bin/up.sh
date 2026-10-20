#!/bin/sh
# Start or rebuild every system: the main project, then eNMEA2000 as its own project.
set -eu
cd "$(dirname "$0")/.."
docker compose up -d --build
docker compose -p enmea --env-file env/enmea.env -f apps/eNMEA2000/compose.yaml -f overrides/enmea.yaml up -d --build

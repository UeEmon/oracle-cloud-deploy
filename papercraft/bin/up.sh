#!/bin/sh
# Start or update the generator.
set -eu
cd "$(dirname "$0")/.."
docker compose up -d --remove-orphans

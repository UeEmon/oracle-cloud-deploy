#!/bin/sh
# Create the API token with a fresh random value. An existing file is never changed.
# Put the same value in Nine-Gage's env/ninegage.env as PAPERCRAFT_API_TOKEN (and keep a copy on the owner's Mac).
set -eu
cd "$(dirname "$0")/.."
umask 077
mkdir -p env
if [ ! -f env/papercraft.env ]; then
	printf 'PAPERCRAFT_API_TOKEN=%s\n' "$(openssl rand -hex 32)" > env/papercraft.env
	echo "created env/papercraft.env"
fi

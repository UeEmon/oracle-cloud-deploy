#!/bin/sh
# Create the settings of the apps that need nothing from the owner, with fresh random secrets.
# Existing files are never changed. Read a token on the VM, e.g. grep BACCHUS_USERS env/bacchus.env
set -eu
cd "$(dirname "$0")/.."
umask 077
mkdir -p env
if [ ! -f env/bacchus.env ]; then
	# The owner's token for the shared stock. Add GEMINI_API_KEY and GEMINI_MODEL here to read labels with AI.
	printf "BACCHUS_USERS='{\"%s\": \"owner\"}'\nGEMINI_API_KEY=\nGEMINI_MODEL=\n" "$(openssl rand -hex 24)" > env/bacchus.env
	echo "created env/bacchus.env"
fi

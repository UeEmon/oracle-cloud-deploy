#!/bin/sh
# Create the settings of the apps that need nothing from the owner, with fresh random secrets.
# Existing files are never changed. Read a token on the VM, e.g. grep APP_TOKEN env/enmea.env
set -eu
cd "$(dirname "$0")/.."
umask 077
mkdir -p env
if [ ! -f env/enmea.env ]; then
	printf 'APP_TOKEN=%s\nPOSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 32)" "$(openssl rand -hex 24)" > env/enmea.env
	echo "created env/enmea.env"
fi
if [ ! -f env/bacchus.env ]; then
	# The owner's token for the shared stock. Add GEMINI_API_KEY and GEMINI_MODEL here to read labels with AI.
	printf "BACCHUS_USERS='{\"%s\": \"owner\"}'\nGEMINI_API_KEY=\nGEMINI_MODEL=\n" "$(openssl rand -hex 24)" > env/bacchus.env
	echo "created env/bacchus.env"
fi
if [ ! -f env/altpnt.env ]; then
	# LiteLLM (LLM analysis) stays off on this VM; add ANTHROPIC_API_KEY here and start it by hand if wanted.
	printf 'LITELLM_MASTER_KEY=sk-%s\nANTHROPIC_API_KEY=\nOPENAI_API_KEY=\nOLLAMA_API_BASE=\nCLOUD_BIND=127.0.0.1\n' "$(openssl rand -hex 24)" > env/altpnt.env
	echo "created env/altpnt.env"
fi

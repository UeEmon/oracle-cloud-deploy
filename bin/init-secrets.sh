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
if [ ! -f env/ninegage.env ]; then
	# Nine-Gage's AI. All optional: an empty key means visitors type their own in the app's AI settings.
	cat > env/ninegage.env <<'EOT'
AI_DEFAULT_PROVIDER=anthropic
ANTHROPIC_API_KEY=
ANTHROPIC_MODEL=
OPENAI_API_KEY=
OPENAI_MODEL=
GEMINI_API_KEY=
GEMINI_MODEL=
# OpenAI-compatible server reachable from the VM (Ollama and so on). localhost here is the container itself.
LOCAL_LLM_BASE_URL=
LOCAL_LLM_MODEL=
LOCAL_LLM_API_KEY=
EOT
	echo "created env/ninegage.env"
fi

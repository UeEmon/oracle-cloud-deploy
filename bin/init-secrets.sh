#!/bin/sh
# Create the settings of the apps that need nothing from the owner, with fresh random secrets.
# Existing values are never changed (Nine-Gage's first admin is only added when missing). Read a token on the VM, e.g. grep BACCHUS_USERS env/bacchus.env
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
	# Nine-Gage's fallback AI keys. All optional: the admin can set them in the app instead.
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
# Nine-Gage's first admin, used only while the app has no users. Added to an existing file too.
# Read it on the VM: grep NINEGAGE_ADMIN env/ninegage.env
if ! grep -q '^NINEGAGE_ADMIN_PASSWORD=.' env/ninegage.env; then
	[ -z "$(tail -c1 env/ninegage.env)" ] || echo >> env/ninegage.env
	sed -i '/^NINEGAGE_ADMIN_\(USER\|PASSWORD\)=/d' env/ninegage.env
	printf 'NINEGAGE_ADMIN_USER=admin\nNINEGAGE_ADMIN_PASSWORD=%s\n' "$(openssl rand -base64 18 | tr -d '/+=')" >> env/ninegage.env
	echo "added the Nine-Gage first admin to env/ninegage.env"
fi
# Nine-Gage's key for encrypting the API keys that general users save for themselves.
# Kept out of the data volume on purpose. Never change it: saved user keys could no longer be read.
if ! grep -q '^NINEGAGE_SECRET_KEY=.' env/ninegage.env; then
	[ -z "$(tail -c1 env/ninegage.env)" ] || echo >> env/ninegage.env
	sed -i '/^NINEGAGE_SECRET_KEY=/d' env/ninegage.env
	printf 'NINEGAGE_SECRET_KEY=%s\n' "$(openssl rand -hex 32)" >> env/ninegage.env
	echo "added the Nine-Gage secret key to env/ninegage.env"
fi
# Nine-Gage's mail for sign-up confirmation. Empty means sign-up is closed until the owner fills it in, e.g.
# NINEGAGE_SMTP_URL=smtps://you%40gmail.com:APP_PASSWORD@smtp.gmail.com:465 and NINEGAGE_MAIL_FROM="Nine-Gage <you@gmail.com>"
if ! grep -q '^NINEGAGE_SMTP_URL=' env/ninegage.env; then
	[ -z "$(tail -c1 env/ninegage.env)" ] || echo >> env/ninegage.env
	printf 'NINEGAGE_SMTP_URL=\nNINEGAGE_MAIL_FROM=\n' >> env/ninegage.env
	echo "added empty Nine-Gage mail settings to env/ninegage.env"
fi

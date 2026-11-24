#!/bin/sh
# Create the secrets that need nothing from the owner, with fresh random values. Existing files are never changed.
# Copy the production secrets to the owner's Mac (~/.chuck-deploy/ninegage/): without NINEGAGE_SECRET_KEY and
# NINEGAGE_BACKUP_KEY a backup cannot be restored with its saved API keys.
set -eu
cd "$(dirname "$0")/.."
umask 077
mkdir -p env
rand() { openssl rand -base64 18 | tr -d '/+='; }
# Production. When moving from CHUCK's VM, copy that VM's env/ninegage.env here instead (same keys, same users),
# then run this script again to add NINEGAGE_BACKUP_KEY.
if [ ! -f env/ninegage.env ]; then
	cat > env/ninegage.env <<EOT
NINEGAGE_ADMIN_USER=admin
NINEGAGE_ADMIN_PASSWORD=$(rand)
NINEGAGE_SECRET_KEY=$(openssl rand -hex 32)
# Sign-up confirmation mail. Empty means sign-up is closed, e.g.
# NINEGAGE_SMTP_URL=smtps://you%40gmail.com:APP_PASSWORD@smtp.gmail.com:465 and NINEGAGE_MAIL_FROM="Nine-Gage <you@gmail.com>"
NINEGAGE_SMTP_URL=
NINEGAGE_MAIL_FROM=
AI_DEFAULT_PROVIDER=anthropic
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
GEMINI_API_KEY=
# In-app improvement requests become GitHub Issues with this fine-grained token (Nine-Gage-Systems only, Issues: Read and write).
# Empty means requests are only kept in the admin screen.
NINEGAGE_FEEDBACK_GITHUB_TOKEN=
EOT
	echo "created env/ninegage.env"
fi
# The key that encrypts the daily backup (scripts/backup.mjs in the app). Never change it: old backups need it.
if ! grep -q '^NINEGAGE_BACKUP_KEY=.' env/ninegage.env; then
	[ -z "$(tail -c1 env/ninegage.env)" ] || echo >> env/ninegage.env
	sed -i '/^NINEGAGE_BACKUP_KEY=/d' env/ninegage.env
	printf 'NINEGAGE_BACKUP_KEY=%s\n' "$(openssl rand -hex 32)" >> env/ninegage.env
	echo "added NINEGAGE_BACKUP_KEY to env/ninegage.env"
fi
# Staging: its own first admin and key, no mail, no AI keys. Read the admin with: grep NINEGAGE_ADMIN env/ninegage-staging.env
if [ ! -f env/ninegage-staging.env ]; then
	printf 'NINEGAGE_ADMIN_USER=admin\nNINEGAGE_ADMIN_PASSWORD=%s\nNINEGAGE_SECRET_KEY=%s\nNINEGAGE_SMTP_URL=\nNINEGAGE_MAIL_FROM=\nAI_DEFAULT_PROVIDER=anthropic\n' \
		"$(rand)" "$(openssl rand -hex 32)" > env/ninegage-staging.env
	echo "created env/ninegage-staging.env"
fi
# The staging site's password, asked by Caddy (user "staging"). Give it to co-developers. Read it with: grep password env/staging-auth.env
if [ ! -f env/staging-auth.env ]; then
	password=$(rand)
	hash=$(docker run --rm caddy:2.8.4 caddy hash-password --plaintext "$password")
	# Single quotes: Compose would otherwise read the $ in the hash as variables.
	printf "# password: %s\nNINEGAGE_STAGING_USER=staging\nNINEGAGE_STAGING_PASSWORD_HASH='%s'\n" "$password" "$hash" > env/staging-auth.env
	echo "created env/staging-auth.env"
fi
# The papercraft generator's API token, read by both papercraft and nine-gage (compose.yaml).
if [ ! -f env/papercraft.env ]; then
	printf 'PAPERCRAFT_API_TOKEN=%s\n' "$(openssl rand -hex 32)" > env/papercraft.env
	echo "created env/papercraft.env"
fi
# The terminal: its own login cookie key, and the handoff key it shares with production (nine-gage).
# Files from before the rename (share → terminal, 2026-11-24) keep their values, so logins and the handoff carry on.
if [ ! -f env/terminal.env ] && [ -f env/share.env ]; then
	sed 's/^SHARE_SESSION_SECRET=/TERMINAL_SESSION_SECRET=/' env/share.env > env/terminal.env
	echo "created env/terminal.env from env/share.env"
fi
if [ ! -f env/terminal-link.env ] && [ -f env/share-link.env ]; then
	sed 's/^SENROLAB_SHARE_SECRET=/SENROLAB_TERMINAL_SECRET=/' env/share-link.env > env/terminal-link.env
	echo "created env/terminal-link.env from env/share-link.env"
fi
if [ ! -f env/terminal.env ]; then
	printf 'TERMINAL_SESSION_SECRET=%s\n' "$(openssl rand -hex 32)" > env/terminal.env
	echo "created env/terminal.env"
fi
if [ ! -f env/terminal-link.env ]; then
	printf 'SENROLAB_TERMINAL_SECRET=%s\n' "$(openssl rand -hex 32)" > env/terminal-link.env
	echo "created env/terminal-link.env"
fi

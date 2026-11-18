#!/bin/sh
# Refuse to start Nine-Gage's VM with a local build, missing secrets, extra ports or a shared network.
set -eu
cd "$(dirname "$0")/.."
config=$(docker compose config --format json)
py() { printf '%s' "$config" | python3 -c "import json,sys;c=json.load(sys.stdin);s=c['services'];$1"; }
fail() { echo "$*" >&2; exit 1; }
[ "$(py "print(' '.join(sorted(s)))")" = "https-proxy nine-gage nine-gage-staging papercraft share" ] || fail "only https-proxy, nine-gage, nine-gage-staging, papercraft and share may run here"
for svc in nine-gage nine-gage-staging; do
	case "$(py "print('' if 'build' in s['$svc'] else s['$svc'].get('image',''))")" in
		ghcr.io/ueemon/nine-gage-systems:?*) ;;
		*) fail "$svc must run ghcr.io/ueemon/nine-gage-systems:<tag> without build" ;;
	esac
	[ "$(py "print(len(s['$svc'].get('ports') or []))")" = 0 ] || fail "$svc must not publish host ports"
	[ "$(py "e=s['$svc']['environment'];print(e.get('NODE_ENV'),e.get('NINEGAGE_DATA_DIR'))")" = "production /data" ] || fail "$svc needs NODE_ENV=production and NINEGAGE_DATA_DIR=/data"
	[ "$(py "e=s['$svc']['environment'];print(1 if e.get('NINEGAGE_ADMIN_USER') and len(e.get('NINEGAGE_ADMIN_PASSWORD',''))>=10 and len(e.get('NINEGAGE_SECRET_KEY',''))>=32 else 0)")" = 1 ] \
		|| fail "$svc needs NINEGAGE_ADMIN_USER, a NINEGAGE_ADMIN_PASSWORD of 10+ and a NINEGAGE_SECRET_KEY of 32+ characters (bin/init-secrets.sh)"
done
[ "$(py "print(1 if len(s['nine-gage']['environment'].get('NINEGAGE_BACKUP_KEY',''))>=32 else 0)")" = 1 ] || fail "env/ninegage.env needs a NINEGAGE_BACKUP_KEY of 32+ characters (bin/init-secrets.sh)"
[ "$(py "print(s['nine-gage']['environment'].get('NINEGAGE_PUBLIC_URL',''))")" = "https://$(py "print(s['https-proxy']['environment']['NINEGAGE_DOMAIN'])")" ] || fail "nine-gage NINEGAGE_PUBLIC_URL must be https://<NINEGAGE_DOMAIN>"
# Each app on its own network, shared only with Caddy.
nets() { py "print(' '.join(sorted((s['$1'].get('networks') or {'default':None}).keys())))"; }
[ "$(nets nine-gage)" = "papercraft prod-edge" ] || fail "nine-gage must be on prod-edge and papercraft only, got '$(nets nine-gage)'"
[ "$(nets nine-gage-staging)" = staging-edge ] || fail "nine-gage-staging must be on staging-edge only, got '$(nets nine-gage-staging)'"
# The papercraft generator: CI image, no host port, reachable only from nine-gage, with a shared token.
case "$(py "print('' if 'build' in s['papercraft'] else s['papercraft'].get('image',''))")" in
	ghcr.io/ueemon/ai-paper-modelar:?*) ;;
	*) fail "papercraft must run ghcr.io/ueemon/ai-paper-modelar:<tag> without build" ;;
esac
[ "$(py "print(len(s['papercraft'].get('ports') or []))")" = 0 ] || fail "papercraft must not publish host ports"
[ "$(nets papercraft)" = papercraft ] || fail "papercraft must be on its own network only, got '$(nets papercraft)'"
[ "$(nets https-proxy | tr ' ' '\n' | grep -c '^papercraft$' || true)" = 0 ] || fail "Caddy must not join the papercraft network"
[ "$(py "a=s['papercraft']['environment'].get('PAPERCRAFT_API_TOKEN','');b=s['nine-gage']['environment'].get('PAPERCRAFT_API_TOKEN','');print(1 if len(a)>=32 and a==b else 0)")" = 1 ] \
	|| fail "env/papercraft.env needs a PAPERCRAFT_API_TOKEN of 32+ characters, the same for both (bin/init-secrets.sh)"
[ "$(py "print(s['nine-gage']['environment'].get('PAPERCRAFT_URL',''))")" = http://papercraft:8086 ] || fail "nine-gage PAPERCRAFT_URL must be http://papercraft:8086"
# The sharing site: CI image, no host port, only Caddy reaches it, its own cookie key, the same handoff key as production.
case "$(py "print('' if 'build' in s['share'] else s['share'].get('image',''))")" in
	ghcr.io/ueemon/nine-gage-share:?*) ;;
	*) fail "share must run ghcr.io/ueemon/nine-gage-share:<tag> without build" ;;
esac
[ "$(py "print(len(s['share'].get('ports') or []))")" = 0 ] || fail "share must not publish host ports"
[ "$(nets share)" = share-edge ] || fail "share must be on share-edge only, got '$(nets share)'"
[ "$(py "e=s['share']['environment'];print(e.get('NODE_ENV'),e.get('SHARE_DATA_DIR'))")" = "production /data" ] || fail "share needs NODE_ENV=production and SHARE_DATA_DIR=/data"
[ "$(py "print(1 if len(s['share']['environment'].get('SHARE_SESSION_SECRET',''))>=32 else 0)")" = 1 ] || fail "env/share.env needs a SHARE_SESSION_SECRET of 32+ characters (bin/init-secrets.sh)"
[ "$(py "a=s['share']['environment'].get('SENROLAB_SHARE_SECRET','');b=s['nine-gage']['environment'].get('SENROLAB_SHARE_SECRET','');print(1 if len(a)>=32 and a==b else 0)")" = 1 ] \
	|| fail "env/share-link.env needs a SENROLAB_SHARE_SECRET of 32+ characters, the same for share and nine-gage (bin/init-secrets.sh)"
domain=$(py "print(s['https-proxy']['environment']['NINEGAGE_DOMAIN'])")
[ "$(py "print(s['share']['environment'].get('SENROLAB_URL',''))")" = "https://$domain" ] || fail "share SENROLAB_URL must be https://<NINEGAGE_DOMAIN>"
[ "$(py "print(s['nine-gage']['environment'].get('SENROLAB_SHARE_URL',''))")" = "https://share.$domain" ] || fail "nine-gage SENROLAB_SHARE_URL must be https://share.<NINEGAGE_DOMAIN>"
[ "$(py "print(s['nine-gage-staging']['environment'].get('SENROLAB_SHARE_SECRET',''))")" = "" ] || fail "staging must not hold the sharing site's handoff key"
[ "$(nets https-proxy | tr ' ' '\n' | grep -c '^share-edge$' || true)" = 1 ] || fail "Caddy must be on share-edge to reach the sharing site"
# Caddy's staging password (docker compose config prints each $ as $$).
[ "$(py "h=s['https-proxy']['environment'].get('NINEGAGE_STAGING_PASSWORD_HASH','').replace('\$\$','\$');print(1 if h.startswith('\$2') and len(h)>50 else 0)")" = 1 ] \
	|| fail "env/staging-auth.env needs NINEGAGE_STAGING_PASSWORD_HASH (bin/init-secrets.sh)"
echo "config OK"

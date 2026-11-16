#!/bin/sh
# Refuse to start the papercraft VM with a local build, a public port, a missing token or extra services.
set -eu
cd "$(dirname "$0")/.."
config=$(docker compose config --format json)
py() { printf '%s' "$config" | python3 -c "import json,sys;c=json.load(sys.stdin);s=c['services'];$1"; }
fail() { echo "$*" >&2; exit 1; }
[ "$(py "print(' '.join(sorted(s)))")" = "papercraft" ] || fail "only papercraft may run here"
case "$(py "print('' if 'build' in s['papercraft'] else s['papercraft'].get('image',''))")" in
	ghcr.io/ueemon/ai-paper-modelar:?*) ;;
	*) fail "papercraft must run ghcr.io/ueemon/ai-paper-modelar:<tag> without build" ;;
esac
# One port, 8080, on a private address (10.x, 172.16-31.x or 192.168.x) only.
ports=$(py "print(' '.join(f\"{p.get('host_ip','')}:{p.get('published','')}:{p.get('target','')}\" for p in s['papercraft'].get('ports') or []))")
case "$ports" in
	10.*:8080:8080 | 192.168.*:8080:8080 | 172.1[6-9].*:8080:8080 | 172.2[0-9].*:8080:8080 | 172.3[01].*:8080:8080) ;;
	*) fail "papercraft must publish only 8080 on this VM's private IP, got '$ports'" ;;
esac
[ "$(py "print(1 if len(s['papercraft']['environment'].get('PAPERCRAFT_API_TOKEN',''))>=32 else 0)")" = 1 ] \
	|| fail "env/papercraft.env needs a PAPERCRAFT_API_TOKEN of 32+ characters (bin/init-secrets.sh)"
echo "config OK"

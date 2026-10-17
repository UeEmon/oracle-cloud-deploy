#!/bin/sh
# Clone or fast-forward each app under apps/. Pass a ref to pin CHUCK, e.g. a branch or tag.
set -eu
cd "$(dirname "$0")/.."
mkdir -p apps
fetch() {
	dir=apps/$1 url=$2 ref=$3
	if [ -d "$dir/.git" ]; then
		git -C "$dir" fetch --quiet origin "$ref"
		git -C "$dir" checkout --quiet -B "$ref" FETCH_HEAD
	else
		git clone --quiet --branch "$ref" "$url" "$dir"
	fi
}
# CHUCK is the public edition; the main line stays private.
fetch CHUCK https://github.com/${CHUCK_REPO:-UeEmon/CHUCK-public-}.git "${CHUCK_REF:-main}"
fetch ai-requirements-navigator https://github.com/UeEmon/ai-requirements-navigator.git "${ARN_REF:-main}"
# 要件ナビ's compose reads env_file .env in its own folder.
ln -sf ../../../../env/arn.env apps/ai-requirements-navigator/deploy/docker/.env

#!/usr/bin/env bash
# The ONLY thing the CI deploy key can do.
#
# Installed at /srv/server-registry/ci-deploy.sh by ci-authorize.sh, and named as a forced command in
# authorized_keys. Whatever the client asks for, sshd runs THIS and puts the requested command in
# SSH_ORIGINAL_COMMAND -- so the key cannot open a shell, read a file, or run anything else. All it
# can express is "deploy version X".
#
# That matters because the private half lives in GitHub Actions secrets, in a PUBLIC repo. Anyone who
# can trigger a workflow can use this key; a forced command is what keeps that from meaning "anyone
# who can trigger a workflow has a root shell".
set -euo pipefail

DEPLOY_URL="https://raw.githubusercontent.com/rc4l/server-registry-rc4l/main/deploy.sh"
VERSION="${SSH_ORIGINAL_COMMAND:-}"

# Nothing but a version number gets through. This is the trust boundary: the string arrives from CI
# and is about to become an argument, so it is validated here rather than assumed upstream.
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
	echo "refused: expected a version like 0.0.3, got '${VERSION}'" >&2
	exit 2
fi

echo "==> ci-deploy: requested version ${VERSION}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Cache-bust. raw.githubusercontent.com serves through a CDN with a few minutes of TTL, so a deploy
# run shortly after a push to deploy.sh silently executes the PREVIOUS version -- which is how a fix
# to that script appeared to do nothing twice in a row. A deploy should run the script as it is now,
# not as it was when someone else last asked for it.
curl -fsSL -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
	"${DEPLOY_URL}?t=$(date +%s)" -o "$tmp"
bash "$tmp" "$VERSION"

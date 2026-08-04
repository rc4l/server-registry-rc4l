#!/usr/bin/env bash
# Authorise a CI deploy key on this host. Run once, on the registry host, as the user CI will log in
# as (root on a stock droplet).
#
#   curl -fsSL https://raw.githubusercontent.com/rc4l/server-registry-rc4l/main/ci-authorize.sh \
#     | bash -s -- 'ssh-ed25519 AAAA... zandrox-ci-deploy'
#
# It installs ci-deploy.sh and adds an authorized_keys entry that pins the key to it. The key gets no
# shell, no port forwarding, no agent forwarding, and no ability to run anything but a deploy -- see
# ci-deploy.sh for why that restriction is the point rather than a nicety.
#
# Re-running is safe: the entry is replaced, not duplicated.
set -euo pipefail

PUBKEY="${1:-}"
if [ -z "$PUBKEY" ]; then
	echo "!! usage: ci-authorize.sh '<ssh-ed25519 AAAA... comment>'" >&2
	exit 1
fi
case "$PUBKEY" in
	ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*) ;;
	*) echo "!! that does not look like an SSH public key" >&2; exit 1 ;;
esac

DIR="${SERVER_REGISTRY_DIR:-/srv/server-registry}"
WRAPPER="${DIR}/ci-deploy.sh"
MARKER="zandrox-ci-deploy"

echo "==> installing ${WRAPPER}"
mkdir -p "$DIR"
curl -fsSL "https://raw.githubusercontent.com/rc4l/server-registry-rc4l/main/ci-deploy.sh" -o "$WRAPPER"
chmod 750 "$WRAPPER"

AUTH="${HOME}/.ssh/authorized_keys"
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
touch "$AUTH"
chmod 600 "$AUTH"

# Drop any previous entry for this key so re-running upgrades rather than accumulates.
if grep -q "$MARKER" "$AUTH" 2>/dev/null; then
	echo "==> replacing the existing ${MARKER} entry"
	grep -v "$MARKER" "$AUTH" > "${AUTH}.new" || true
	mv "${AUTH}.new" "$AUTH"
	chmod 600 "$AUTH"
fi

# restrict = no pty, no forwarding of any kind, no user rc file. command= = this key runs one program.
printf 'restrict,command="%s" %s\n' "$WRAPPER" "$PUBKEY" >> "$AUTH"

echo "==> authorised. This key can now run exactly one thing:"
echo "      ${WRAPPER} <version>"
echo "==> verify from CI with:  ssh <user>@<host> 0.0.3"

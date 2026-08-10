#!/usr/bin/env bash
# Deploy or upgrade this server registry.
#
#   curl -fsSL https://raw.githubusercontent.com/rc4l/server-registry-rc4l/main/deploy.sh | bash
#   curl -fsSL .../deploy.sh | bash -s -- 0.0.3      # pin a different version
#
# One curl line because a provider's browser console typically cannot paste newlines. Idempotent: re-run
# it to upgrade, and the ban lists survive. The container carries `restart: always`, so this is a
# ONE-TIME setup -- re-run only to change version.
set -euo pipefail

VERSION="${1:-0.0.3}"
DIR="${SERVER_REGISTRY_DIR:-/srv/server-registry}"
PORT=15300

echo "==> ZandroX server registry ${VERSION} -> ${DIR}"

command -v docker >/dev/null || { echo "!! docker is not installed" >&2; exit 1; }
# Compose v2 is a docker subcommand; v1 was a separate binary. Support both rather than assume.
if docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then COMPOSE="docker-compose"
else echo "!! neither 'docker compose' nor 'docker-compose' found" >&2; exit 1; fi

# uid 1000 is the non-root `registry` user inside the image. Without this the daemon cannot write to
# its own volume -- and CI cannot catch it, because the smoke test runs with no mount.
mkdir -p "${DIR}/data"
chown -R 1000:1000 "${DIR}/data"

# Create the four IP lists empty. The daemon runs fine without them, but it logs four
# "could not open" warnings that read like errors -- and an operator cannot discover which files
# exist without reading engine source.
for f in banlist.txt whitelist.txt blocklist.txt multiserver_whitelist.txt; do
	[ -e "${DIR}/data/${f}" ] || install -o 1000 -g 1000 -m 644 /dev/null "${DIR}/data/${f}"
done

cat > "${DIR}/docker-compose.yml" <<EOF
services:
  server-registry:
    image: ghcr.io/rc4l/forkundera-server-registry:${VERSION}
    container_name: server-registry
    restart: always
    ports:
      - "${PORT}:${PORT}/udp"
    volumes:
      - ./data:/data
EOF

# Keep the CI forced command in step with the repo, on hosts that use one.
#
# ci-deploy.sh is installed on the host rather than fetched per call, so without this, changing it
# meant someone re-running ci-authorize.sh by hand -- a manual step in the middle of a setup whose
# entire point was removing manual steps.
#
# This grants nothing new: deploy.sh is already fetched from the same repo and run as root, so anyone
# able to alter it could rewrite authorized_keys directly. The constraint on the deploy key was never
# stronger than "whoever controls this repo", and self-updating does not change that.
#
# Only ever an UPGRADE, never an install: if no forced command exists, this host has not authorised CI
# and should not silently acquire it. Written to a temp file and renamed, because this script may be
# running as a child of the very file being replaced -- rename swaps the inode and leaves the running
# process reading the old one, where `curl -o` onto the live path would truncate it mid-execution.
CI_WRAPPER="${DIR}/ci-deploy.sh"
if [ -f "$CI_WRAPPER" ]; then
	if curl -fsSL -H 'Cache-Control: no-cache' \
		"https://raw.githubusercontent.com/rc4l/server-registry-rc4l/main/ci-deploy.sh?t=$(date +%s)" \
		-o "${CI_WRAPPER}.new" 2>/dev/null; then
		chmod 750 "${CI_WRAPPER}.new"
		mv "${CI_WRAPPER}.new" "$CI_WRAPPER"
		echo "==> refreshed the CI forced command"
	else
		rm -f "${CI_WRAPPER}.new"
		echo "==> NOTE: could not refresh the CI forced command; keeping the installed one"
	fi
fi

# Best-effort: a host may use ufw, nftables, a cloud firewall, or nothing. Never fail the deploy over
# it, but say so -- a silently unreachable registry looks exactly like a broken one.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
	ufw allow "${PORT}/udp" >/dev/null 2>&1 && echo "==> ufw: opened ${PORT}/udp"
else
	echo "==> NOTE: ufw not active. Ensure UDP ${PORT} is open (host firewall / provider firewall)"
fi

cd "${DIR}"
$COMPOSE pull
$COMPOSE up -d

echo "==> waiting for the daemon"
sleep 4

# The registry's log names every server and client that has talked to it -- IP addresses are the
# entire content of the interesting lines. That is fine on your own terminal and NOT fine when this
# script runs from CI, whose output is public: one deploy publishes the address of everyone connected
# at that moment.
#
# So print the log only when a human is watching, or when something has actually gone wrong, and mask
# addresses whenever stdout is not a terminal. Found the hard way -- the first automated deploy put a
# home IP into a public Actions log.
show_logs() {
	if [ -t 1 ]; then
		$COMPOSE logs --tail=20
	else
		$COMPOSE logs --tail=20 | sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<ip>/g'
	fi
}

[ -t 1 ] && show_logs

# Assert it is up rather than leaving the operator to read logs: a container that starts and
# immediately dies still prints a banner.
if [ "$(docker inspect -f '{{.State.Running}}' server-registry 2>/dev/null)" != "true" ]; then
	echo "!! server-registry is NOT running:" >&2
	show_logs >&2
	exit 1
fi
echo "==> OK: running on UDP ${PORT}"

#!/usr/bin/env bash
# Deploy or upgrade this server registry.
#
#   curl -fsSL https://raw.githubusercontent.com/rc4l/server-registry-rc4l/main/deploy.sh | bash
#   curl -fsSL .../deploy.sh | bash -s -- 0.0.3      # pin a different version
#
# One curl line because the DigitalOcean browser console cannot paste newlines. Idempotent: re-run
# it to upgrade, and the ban lists survive. The container carries `restart: always`, so this is a
# ONE-TIME setup -- re-run only to change version.
set -euo pipefail

VERSION="${1:-0.0.2}"
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
    image: ghcr.io/rc4l/zandrox-server-registry:${VERSION}
    container_name: server-registry
    restart: always
    ports:
      - "${PORT}:${PORT}/udp"
    volumes:
      - ./data:/data
EOF

# Best-effort: a host may use ufw, nftables, a cloud firewall, or nothing. Never fail the deploy over
# it, but say so -- a silently unreachable registry looks exactly like a broken one.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
	ufw allow "${PORT}/udp" >/dev/null 2>&1 && echo "==> ufw: opened ${PORT}/udp"
else
	echo "==> NOTE: ufw not active. Ensure UDP ${PORT} is open (DigitalOcean cloud firewall?)"
fi

cd "${DIR}"
$COMPOSE pull
$COMPOSE up -d

echo "==> waiting for the daemon"
sleep 4
$COMPOSE logs --tail=20

# Assert it is up rather than leaving the operator to read logs: a container that starts and
# immediately dies still prints a banner.
if [ "$(docker inspect -f '{{.State.Running}}' server-registry 2>/dev/null)" != "true" ]; then
	echo "!! server-registry is NOT running -- see the log above" >&2
	exit 1
fi
echo "==> OK: running on UDP ${PORT}"

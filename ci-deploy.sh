#!/usr/bin/env bash
# The ONLY things the CI deploy key can do.
#
# Installed at /srv/server-registry/ci-deploy.sh by ci-authorize.sh, and named as a forced command in
# authorized_keys. Whatever the client asks for, sshd runs THIS and puts the requested command in
# SSH_ORIGINAL_COMMAND -- so the key cannot open a shell, read a file, or run anything else.
#
# That matters because the private half lives in GitHub Actions secrets, in a PUBLIC repo. Anyone who
# can trigger a workflow can use this key; a forced command is what keeps that from meaning "anyone
# who can trigger a workflow has a root shell".
#
# Two verbs, both read-only or idempotent:
#
#   <x.y.z>          deploy that image version
#   logs [minutes]   print recent container logs, IP addresses masked
#
# `logs` exists because the alternative was a console session, which is what this whole setup was
# meant to remove. Without it the registry's own log -- the only place that says whether a server's
# inbound port is reachable -- is unreadable to the people operating it.
set -euo pipefail

DEPLOY_URL="https://raw.githubusercontent.com/rc4l/server-registry-rc4l/main/deploy.sh"
REQUEST="${SSH_ORIGINAL_COMMAND:-}"

# Addresses are the entire content of the interesting log lines, and this output is bound for a public
# CI log. Masking here means the host never emits them at all, rather than trusting every future
# caller to strip them -- the guarantee should not depend on who is asking.
mask_ips() {
	sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<ip>/g'
}

case "$REQUEST" in
	logs|logs\ *)
		minutes="${REQUEST#logs}"
		minutes="${minutes// /}"
		[ -z "$minutes" ] && minutes=10
		if ! printf '%s' "$minutes" | grep -Eq '^[0-9]{1,4}$'; then
			echo "refused: logs takes a number of minutes, got '${minutes}'" >&2
			exit 2
		fi
		echo "==> ci-deploy: logs for the last ${minutes}m (addresses masked)"
		cd /srv/server-registry
		if docker compose version >/dev/null 2>&1; then
			docker compose logs --since "${minutes}m" --no-color 2>&1 | mask_ips
		else
			docker-compose logs --since "${minutes}m" --no-color 2>&1 | mask_ips
		fi
		;;

	[0-9]*)
		# This is the trust boundary: the string arrives from CI and is about to become an argument, so
		# it is validated here rather than assumed upstream.
		if ! printf '%s' "$REQUEST" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
			echo "refused: expected a version like 0.0.3, got '${REQUEST}'" >&2
			exit 2
		fi
		echo "==> ci-deploy: requested version ${REQUEST}"

		tmp="$(mktemp)"
		trap 'rm -f "$tmp"' EXIT

		# Cache-bust. raw.githubusercontent.com serves through a CDN with a few minutes of TTL, so a
		# deploy run shortly after a push to deploy.sh silently executes the PREVIOUS version -- which
		# is how a fix to that script appeared to do nothing twice in a row. A deploy should run the
		# script as it is now, not as it was when someone else last asked for it.
		curl -fsSL -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
			"${DEPLOY_URL}?t=$(date +%s)" -o "$tmp"
		bash "$tmp" "$REQUEST"
		;;

	*)
		echo "refused: expected a version like 0.0.3, or 'logs [minutes]'; got '${REQUEST}'" >&2
		exit 2
		;;
esac

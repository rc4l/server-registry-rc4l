# server-registry-rc4l

The deployment and moderation config for **rc4l's ZandroX server registry** — a live instance, kept
public so anyone standing up their own has a working example rather than a blank page.

- **Address:** `registry.cantstopscrolling.net` (UDP 15300)
- **Image:** [`ghcr.io/rc4l/zandrox-server-registry`](https://github.com/rc4l/ZandroX/pkgs/container/zandrox-server-registry)
- **Software:** [ZandroX](https://github.com/rc4l/ZandroX) — `src/zandronum/server-registry/`

## What a server registry does

Servers announce themselves to it every 30 seconds; it drops them after 60 without a heartbeat. A
client asking for the list gets back **addresses only** — every detail the browser shows (name, map,
players, ping) comes from querying each server directly.

That is why it needs no database and no backups: restart it and the list repopulates within a
minute. The only durable state is the four IP lists in `data/`.

## Run your own

```
curl -fsSL https://raw.githubusercontent.com/rc4l/server-registry-rc4l/main/deploy.sh | bash
```

One line because a browser console cannot paste newlines. Re-run it to upgrade — the ban lists
survive. It is a **one-time** setup: the container carries `restart: always`, so it comes back after
a reboot without help.

Then point a server at it:

```
fua_serverregistry_host "registry.cantstopscrolling.net"
sv_fua_serverregistry_announce 1
```

Watch `docker compose logs -f`; a working announce looks like:

```
+ Adding <ip>:10666 (revision …) to the verification list.
+ Adding <ip>:10666 (revision …) to the server list.
-> Banlist sent to <ip>:10666.
<ip>:10666 acknowledged receipt of the banlist.
```

### DNS: do not proxy it

If you put this behind Cloudflare, the record must be **DNS only (grey cloud)**. Cloudflare's proxy
handles HTTP/HTTPS, not UDP — turn the orange cloud on and traffic never reaches the host, with no
error, just servers that quietly stop appearing.

## Moderation policy

This registry **hides servers that do not enforce its ban list** (`sv_fua_serverregistry_enforcebans
false`). Listing here means accepting these bans. That is a deliberate choice and not a demand:
registries are federated, so a server that declines can advertise on one that does not enforce.
Refusing a listing is a redirect, not exile.

Server operators can always opt out — enforcement is a CVAR on their side, never compelled by us.

## The lists in `data/`

| file | who it affects |
|---|---|
| `banlist.txt` | players banned network-wide — **pushed to every listed server** |
| `whitelist.txt` | exemptions from the above, also pushed |
| `blocklist.txt` | hosts blocked from listing here (they can still browse) |
| `multiserver_whitelist.txt` | hosts permitted to register more than one server |

All four are re-read **every 15 minutes**, so an edit applies without a restart.

### Why the current lists are empty

They start empty and stay empty until there is a reason. Running an independent registry means
inheriting nobody else's ban decisions — that is the point of running one.

### On publishing bans

Current state is published here for accountability. Note that entries are **IP addresses**, which are
personal data, and that home addresses are shared and reassigned — a ban today can land on a
stranger in six months. Entries are therefore kept current rather than accumulated, and removed once
they stop being useful.

## Licence

Config and scripts: GPL-3.0-or-later, matching ZandroX.

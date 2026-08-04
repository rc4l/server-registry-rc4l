# server-registry-rc4l

The infrastructure behind rc4l's corner of the ZandroX network, kept public so anyone standing up
their own has a working example rather than a blank page.

Two separate things live here:

| | |
|---|---|
| **The server registry** | `registry.cantstopscrolling.net` (UDP 15300) — the daemon servers announce to |
| **[`serverregistrylist-cdn/`](serverregistrylist-cdn/)** | `registrylist.cantstopscrolling.net` — a Cloudflare Worker caching the list of registries clients trust |

They are unrelated in function and share only an operator. The registry is a UDP daemon whose DNS
record must never be proxied; the Worker is HTTPS and must be. Both are here because both are
*deployment*, which is what this repo is for.

**Neither owns the trust list.** That file lives in the
[engine repo](https://github.com/rc4l/ZandroX/blob/main/serverregistries.txt), so it forks with the
engine and no single registry becomes the authority over the list it is merely listed on.

- **Image:** [`ghcr.io/rc4l/zandrox-server-registry`](https://github.com/rc4l/ZandroX/pkgs/container/zandrox-server-registry)
- **Software:** [ZandroX](https://github.com/rc4l/ZandroX)

## What a server registry does

Servers announce themselves every 30 seconds; the registry drops them after 60 without a heartbeat.
A client asking for the list gets back **addresses only** — every detail the browser shows (name,
map, players, ping) comes from querying each server directly.

So it needs no database and no backups: restart it and the list repopulates within a minute. The
only durable state is the four IP lists in `data/`.

## Run your own

```
curl -fsSL https://raw.githubusercontent.com/rc4l/server-registry-rc4l/main/deploy.sh | bash
```

One line because a browser console cannot paste newlines. Re-run it to upgrade; the ban lists
survive. It is a **one-time** setup — the container carries `restart: always`, so it returns after a
reboot on its own.

Point a server at it:

```
fua_serverregistry_host "registry.cantstopscrolling.net"
sv_fua_serverregistry_announce 1
```

A working announce looks like this in `docker compose logs -f`:

```
+ Adding <ip>:10666 (revision …) to the verification list.
+ Adding <ip>:10666 (revision …) to the server list.
-> Banlist sent to <ip>:10666.
<ip>:10666 acknowledged receipt of the banlist.
```

## Running one well

Three things worth knowing before you host one, all learned the hard way.

**Never proxy the DNS record.** CDN proxies handle HTTP/HTTPS, not UDP — enable one and traffic
never reaches the host, with no error, just servers that quietly stop appearing. (On Cloudflare that
is the orange cloud; keep it grey.) A plain DNS record also means the host's address is public — the
record *is* the disclosure — which is unavoidable, since the registry must be directly reachable.

**Use a hostname, not a bare IP.** A provider's default IP usually survives reboots but not a
rebuild. Behind a name, an address change is one DNS edit and every server follows automatically;
handing out an IP makes it a coordinated migration. A reserved/floating IP is better still once
other people depend on you.

**A registry is a UDP reflector.** A small request produces a multi-kilobyte server list, and UDP
source addresses are trivially spoofed. Built-in flood protection is per-source-IP, which does not
stop spoofed reflection. The risk is not the registry falling over — it is the *host* emitting a
flood and getting rate-limited by its provider, so give it a box whose fate you are happy to share.

## Moderation policy

This registry **hides servers that do not enforce its ban list**
(`sv_fua_serverregistry_enforcebans false`). Listing here means accepting these bans.

That is a choice, not a demand: registries are federated, so a server that declines can advertise on
one that does not enforce. Refusing a listing is a redirect, not exile. Enforcement is a CVAR on the
operator's side and is never compelled by us.

## The lists in `data/`

| file | who it affects |
|---|---|
| `banlist.txt` | players banned network-wide — **pushed to every listed server** |
| `whitelist.txt` | exemptions from the above, also pushed |
| `blocklist.txt` | hosts blocked from listing here (they can still browse) |
| `multiserver_whitelist.txt` | hosts permitted to register more than one server |

All four are re-read **every 15 minutes**, so an edit applies without a restart.

They start empty and stay empty until there is a reason — running an independent registry means
inheriting nobody else's ban decisions.

On publishing bans: entries are **IP addresses**, which are personal data, and home addresses are
shared and reassigned — a ban today can land on a stranger in six months. Entries are kept current
rather than accumulated.

## Licence

GPL-3.0-or-later, matching ZandroX.

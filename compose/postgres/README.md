# postgres

**Self-hosted PostgreSQL** in a single hardened Docker Compose file —
official `postgres:17-alpine` image, file-based Docker secrets,
scram-sha-256 auth, healthcheck, log rotation, persistent named
volume, `--data-checksums` for early on-disk corruption detection.

> Boilerplate / starter. Review every default before running this in production.
> In particular: fill in `.env` with real credentials (the file ships blank so
> the official image refuses to start without them), decide on a backup
> strategy, set resource limits, and confirm the network exposure matches
> your context.

## Requirements

- Docker Engine 24+
- Docker Compose **v2.20+** (this stack uses `secrets.environment` and the
  top-level `configs:` mapping)

## Quick start

```sh
cp .env.example .env          # edit and set real values
docker compose up -d
docker compose ps             # service should report `healthy` after ~30s
```

Connect from the host (default — loopback only):

```sh
psql -h 127.0.0.1 -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

Connect from another container on the same project: attach it to the
`postgres_net` network and reach the DB at `postgres:5432`.

## What is configured

| Concern         | Default                                                    |
| --------------- | ---------------------------------------------------------- |
| Image           | `postgres:17-alpine`, version-pinned                       |
| Auth            | `scram-sha-256`                                            |
| Secrets         | File-based, sourced from your local credential file        |
| Port binding    | `127.0.0.1:5432` only — not reachable from the LAN         |
| Network         | Bridge (`postgres_net`)                                    |
| Persistence     | Named volume `pg_data`                                     |
| Healthcheck     | `pg_isready` on the configured user/DB, every 10s          |
| Log rotation    | 100MB × 6 files                                            |
| Stop grace      | 30s (gives Postgres time for a clean shutdown)             |

## Customising

### `postgresql.conf`

Mounted via the top-level `configs:` block. Postgres falls back to its image
defaults for anything not set there. Common overrides (memory, connections,
WAL, logging, autovacuum) are listed as commented examples in `postgresql.conf`.

### First-boot init scripts

Uncomment the `./initdb:/docker-entrypoint-initdb.d:ro` mount in `compose.yml`
and drop `*.sql` or `*.sh` files into a local `initdb/` directory. They run
**only** when the data directory is empty — they will not migrate an existing
database.

### Resource limits

Uncomment the `deploy.resources` block in `compose.yml`. As a starting point,
size `memory` to your expected working set plus headroom and set
`shared_buffers` (in `postgresql.conf`) to ~25% of that.

### Networking alternatives

The default is bridge networking with a published port bound to `127.0.0.1`.
The compose file documents an alternative `network_mode: host` setup. Be aware
that on Linux, packets arriving via the docker chain may bypass `ufw` rules —
verify with `iptables -L` if you depend on a host firewall.

## Backups

Not included. Two simple options:

1. **`pg_dump` cron**: schedule `pg_dump` from the host or a sidecar
   container, write to a mounted volume, ship offsite.
2. **Volume snapshots**: snapshot `pg_data` at the storage layer (only safe
   while Postgres is stopped or with a filesystem that supports atomic
   snapshots).

Whatever you choose, **test the restore** on a fresh host before relying on it.

## Production checklist

- [ ] Filled in every blank value in `.env` with real credentials, stored outside the repo
- [ ] Decided whether the loopback-only port binding is correct (LAN? VPN-only?)
- [ ] Set `deploy.resources.limits` to match your host
- [ ] Tuned `shared_buffers`, `work_mem`, and `max_connections` in `postgresql.conf`
- [ ] Configured backups and tested a restore
- [ ] Confirmed log retention (100MB × 6 ≈ 600MB) is enough for your needs

# redis

Standalone Redis — cache, session store, queue backend, anything you'd
reach for with a key-value store.

> Boilerplate / starter. Single-node Redis with password auth and
> sane persistence defaults. For high availability use Redis Sentinel
> or Cluster mode (out of scope here).

## Requirements

- Docker Engine 24+, Docker Compose v2.20+
- A password (the stack refuses to start without `REDIS_PASSWORD`)

## Quick start

### 1. Generate the password and the env file

```sh
cp .env.example .env
# Set REDIS_PASSWORD in .env to:
openssl rand -hex 32
```

### 2. Boot the stack

```sh
docker compose up -d
docker compose ps     # redis should report `healthy` after ~10 seconds
```

### 3. Connect

From the host:

```sh
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" ping
# PONG

# Or from outside the container:
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" ping
```

From an app in another container on the same network (attach the app
to `redis_net` as an external network — see "Connect from another
stack" below):

```
redis://default:${REDIS_PASSWORD}@redis:6379/0
```

## What is configured

| Concern             | Default                                                  |
| ------------------- | -------------------------------------------------------- |
| Image               | `redis:7.4-alpine`, version-pinned                       |
| Auth                | `requirepass` from `REDIS_PASSWORD` (mandatory)          |
| Persistence         | AOF on, `appendfsync everysec` (durable, ~1s data loss window) |
| Bind                | `127.0.0.1:6379` only                                    |
| Healthcheck         | `redis-cli ping` against the configured password         |
| Resource limits     | 256 MB / 0.5 CPU                                         |
| Volume              | `redis-data` named volume                                |
| Log rotation        | 50 MB × 5 files, compressed                              |

## Customising

### Set a memory cap and eviction policy

By default Redis grows until it hits the container memory limit and
then errors on writes (`OOM command not allowed`). To make it evict
instead, uncomment the `--maxmemory` / `--maxmemory-policy` flags in
`compose.yml`. Common policies:

| Policy           | When to use                                             |
| ---------------- | ------------------------------------------------------- |
| `allkeys-lru`    | Generic cache — evict least-recently-used               |
| `volatile-lru`   | Evict only keys with a TTL set; persist untagged keys   |
| `allkeys-lfu`    | Like LRU but counts access frequency (Redis 4+)         |
| `noeviction`     | Refuse writes when full — for queues / session stores   |

If you use Redis as a session store or queue backend, **don't enable
LRU** — `noeviction` is what you want, otherwise you'll silently lose
state.

### Persistence: AOF vs RDB vs none

This stack runs AOF + the default RDB snapshots together. Trade-offs:

- **AOF only** (current default with `--save ""` to disable RDB):
  most durable, slower restarts, larger disk footprint.
- **RDB only** (set `--appendonly no`): faster, smaller, but you can
  lose up to the last save interval (default 1 hour) on crash.
- **Neither** (`--save "" --appendonly no`): pure in-memory cache. Use
  for cache-only workloads where regenerating on restart is fine.

Edit the `command:` block in `compose.yml` to switch.

### Custom redis.conf

If the inline command flags get long, drop a `redis.conf` into
`./config/` and uncomment the matching mount + command in
`compose.yml`. The official documentation lists every directive:
https://redis.io/docs/management/config/

### Connect from another compose stack

In the consumer stack's compose.yml:

```yaml
networks:
  default:
    name: <consumer-stack-name>_net
  redis_net:
    external: true
    name: redis_net

services:
  app:
    networks: [default, redis_net]
    environment:
      - REDIS_URL=redis://default:${REDIS_PASSWORD}@redis:6379/0
```

The consumer stack reads `REDIS_PASSWORD` from its own .env (you'll
have the same value in both `.env` files — pick a secret manager for
real deployments).

### Bumping versions

```sh
# In compose.yml: bump the tag
docker compose pull
docker compose up -d
```

Redis is good about backward compatibility within major versions. For
a major version jump (7.x → 8.x in future), check the upstream
[release notes](https://github.com/redis/redis/releases) — RDB and
AOF formats stay compatible, but a few config defaults shift.

## Backups

Two reasonable approaches:

1. **`redis-cli BGSAVE` + volume tarball**: trigger a background save,
   then snapshot the `redis-data` volume the same way the
   [signoz-sqlite-backup.sh](../signoz/scripts/signoz-sqlite-backup.sh)
   pattern does:

   ```sh
   docker compose exec redis redis-cli -a "$REDIS_PASSWORD" BGSAVE
   # wait for LASTSAVE timestamp to update, then
   docker run --rm -v redis-data:/src:ro -v $PWD/backup:/dst alpine \
       sh -c 'tar czf /dst/redis-$(date +%Y%m%d).tar.gz -C /src .'
   ```

2. **Replication to another Redis**: run a second Redis instance with
   `--slaveof <primary> 6379` and back up that one with the volume
   snapshot pattern. Avoids interrupting the primary.

For pure-cache workloads, no backups needed.

## Security checklist

- [ ] `REDIS_PASSWORD` generated from a CSPRNG (`openssl rand -hex 32`)
      and stored outside the repo
- [ ] Redis port (`6379`) is loopback only OR placed behind a strong
      auth boundary
- [ ] If exposing to the LAN, confirm only intended clients can reach
      `:6379` (firewall / VPC rules)
- [ ] Decided on memory + eviction policy (defaults to OOM on writes
      when full)
- [ ] Decided on persistence model (AOF / RDB / none) per workload
- [ ] Backup strategy chosen if the data is not pure cache

## Troubleshooting

**`NOAUTH Authentication required`**: client is connecting without the
password. Set `REDIS_URL=redis://default:<password>@redis:6379/0` or
the equivalent in your client library.

**Stack fails to start: `set REDIS_PASSWORD in your env file`**: you
forgot to set `REDIS_PASSWORD` in `.env`. The stack refuses to boot
without it.

**`OOM command not allowed when used memory > 'maxmemory'`**: container
hit its memory cap. Either raise the limit (`deploy.resources.limits.memory`),
set a Redis-side `maxmemory` smaller than the container limit and add
`--maxmemory-policy`, or both.

**Slow restart after crash**: AOF is replayed on boot. If your AOF is
multi-GB, consider switching to RDB-only or running `BGREWRITEAOF`
periodically to compact it.

# nginxproxymanager

[Nginx Proxy Manager](https://nginxproxymanager.com) — graphical reverse
proxy + Let's Encrypt automation. Sits in front of one or more upstream
services and handles HTTP routing, SSL termination, and access lists.

> Boilerplate / starter. NPM is internet-facing by design (`:80` /
> `:443`). Change the default admin credentials on first login and
> review the security checklist below before pointing DNS at it.

## Requirements

- Docker Engine 24+, Docker Compose v2.20+
- Inbound `:80` and `:443` open on the host (NPM uses ACME HTTP-01
  challenges by default — port 80 is required even if you only serve
  HTTPS)
- A DNS record for whatever hostname you want NPM to manage

## Quick start

### 1. Generate the env file

```sh
cp .env.example .env
# Fill in every blank value. `docker compose config` will error if any
# required key is missing. Generate passwords with `openssl rand -hex 32`.
# DB_MYSQL_PASSWORD == MYSQL_PASSWORD must match each other (same goes
# for USER and DATABASE / NAME — see comments in .env.example).
```

### 2. Boot the stack

```sh
docker compose up -d
docker compose ps     # both services should report `healthy` after ~1 minute
```

### 3. Log in to the admin UI

The admin UI is loopback-only (`127.0.0.1:81`). Reach it via:

- Local: `http://127.0.0.1:81`
- Remote: SSH local-forward — `ssh -L 81:127.0.0.1:81 host`, then
  open `http://127.0.0.1:81` in your local browser.

**Default first-login credentials (NPM hardcodes these):**

```
Email:    admin@example.com
Password: changeme
```

NPM forces a password change on first login. Do this immediately.

### 4. Add your first proxy host

Hosts → Proxy Hosts → **Add Proxy Host**. Set the public domain, point
at the upstream container's `service-name:port`, and (optionally) request
a Let's Encrypt cert in the SSL tab.

For NPM to reach an upstream container, both stacks must share a Docker
network — either attach the upstream service to `npm_public_net`, or
add an external network on this stack pointing at theirs.

## What is configured

| Concern             | Default                                                 |
| ------------------- | ------------------------------------------------------- |
| NPM image           | `jc21/nginx-proxy-manager:2.11.3`                       |
| Database image      | `mariadb:11.5-noble` (official, smaller than `jc21/mariadb-aria`) |
| Public ports        | `:80` and `:443` on all interfaces                      |
| Admin UI port       | `127.0.0.1:81` only                                     |
| Network split       | `npm_public_net` (default) + `npm_db_net` (internal: true) |
| Database isolation  | DB has no route off the internal network — NPM is the only client |
| Healthchecks        | NPM `/api`, MariaDB `mariadb-admin ping`                |
| Resource limits     | 512 MB / 0.5 CPU each                                   |
| Persistent state    | `npm-data`, `npm-ssl`, `npm-db` named volumes           |
| Log rotation        | 50 MB × 5 files, compressed                             |

## Customising

### Stream (TCP/UDP) proxying

Uncomment the additional ports in `services.npm.ports` (e.g. `:21:21` for
FTP, `:5432:5432` for Postgres). NPM exposes a Streams tab for these
once the port is published.

### Use the upstream `jc21/mariadb-aria` image

`mariadb-aria` ships ARM32 builds, useful on older Raspberry Pi
hardware. Replace the `db` image:

```yaml
db:
  image: jc21/mariadb-aria:10.11.7-mariadb-1
  environment:
    - MYSQL_ROOT_PASSWORD=...   # use MYSQL_* not MARIADB_* with this image
    - MYSQL_DATABASE=...
    - MYSQL_USER=...
    - MYSQL_PASSWORD=...
```

The official `mariadb:11.5-noble` image used by default supports
linux/amd64 and linux/arm64 — sufficient for any modern host.

### Bumping versions

```sh
# In compose.yml: bump tags
docker compose pull
docker compose up -d
```

`MARIADB_AUTO_UPGRADE=1` runs `mysql_upgrade` on boot, so MariaDB minor
bumps are usually drop-in. For NPM major bumps (2.x → 3.x in future)
read the upstream changelog first.

### Backups

Two volumes need backing up:

- `npm-data`: NPM's SQLite-style settings and proxy host definitions
  (smaller, changes often)
- `npm-ssl`: Let's Encrypt accounts and issued certificates (rotate
  quarterly, but a backup avoids re-issuing on disaster recovery)

Adapt the
[`signoz-sqlite-backup.sh`](../signoz/scripts/signoz-sqlite-backup.sh)
pattern with `VOLUME_NAME=npm-data` (and a separate run for
`VOLUME_NAME=npm-ssl`).

The MariaDB volume (`npm-db`) is mostly metadata — back it up if you
want zero-downtime restores; otherwise NPM will rebuild it from the
`npm-data` SQLite on first boot of a fresh deployment.

## Security checklist

- [ ] Filled in every blank value in `.env` with a strong password
- [ ] Logged in to the admin UI and changed the default
      `admin@example.com / changeme` credentials (NPM hardcodes these
      on first boot — they are unrelated to the .env values above)
- [ ] Admin UI port (81) is loopback only OR placed behind a strong
      auth layer
- [ ] DNS pointed at the host only after the above steps
- [ ] Decided on Let's Encrypt rate limit handling (50 certs/week per
      registered domain, 5 duplicate certs/week)
- [ ] Backup strategy chosen (`npm-data` and `npm-ssl` at minimum)
- [ ] Rate limits and IP access lists configured per host as needed

## Troubleshooting

**`Bad Gateway` on a proxy host**: NPM can't reach the upstream. Check
both containers share a Docker network — `docker network inspect
npm_public_net` should list the upstream container. Use the upstream's
container name (not `localhost`) as the forwarded host.

**Let's Encrypt issuance fails**: ACME HTTP-01 needs port 80 open and
the public DNS pointing at the host. Check the Audit Log in NPM
(Settings → Audit Log) and the upstream challenge URL with `curl`.

**Lost the admin password**: there's no recovery flow built in. Either
delete and recreate the user via the SQLite store in the `npm-data`
volume, or restore from a backup.

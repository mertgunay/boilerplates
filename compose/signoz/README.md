# signoz

**Self-hosted [SigNoz](https://signoz.io) observability stack** — a
single pane of glass for traces, logs, and metrics, backed by
ClickHouse + ZooKeeper, with the SigNoz OpenTelemetry Collector
ingesting OTLP on `:4317` (gRPC) and `:4318` (HTTP). This is the
**minimal core**: no reverse proxy, no TLS. The SigNoz UI is
published on `127.0.0.1` only by default.

If you want a hardened nginx reverse proxy with rate limiting and security
headers in front, use [`compose/signoz-with-nginx`](../signoz-with-nginx)
instead.

> Boilerplate / starter. Review every default before running this in
> production. In particular: rotate the JWT secret, set a retention policy
> in the SigNoz UI, decide on a backup schedule, and confirm the network
> exposure matches your context.

## Requirements

- Docker Engine 24+, Docker Compose v2.20+
- ~3 GB RAM headroom for ClickHouse on light load (limit is set to 2 GB,
  reserve 1 GB; tune up for any real workload)
- Disk: ClickHouse grows roughly proportional to ingested telemetry —
  expect hundreds of MB to multiple GB per day depending on volume

## Architecture

```
external app  ──▶  :4317 OTLP gRPC  ──▶  signoz-otel-collector
                  :4318 OTLP HTTP                │
                                                 ▼
                                        ┌────────────────┐
                                        │   ClickHouse   │  ◀── coordinated by ── ZooKeeper
                                        │ traces/metrics │
                                        │ logs/metadata  │
                                        └────────────────┘
                                                 ▲
                                                 │  query
                                            ┌────┴────┐
                                            │ SigNoz  │
                                            │   UI    │  ──▶  alerts (alertmanager built-in)
                                            └─────────┘
                                                 │  state (alert rules, dashboards, users)
                                                 ▼
                                          signoz-sqlite (volume)
```

`signoz-telemetrystore-migrator` and `init-clickhouse` are one-shot helpers
that prepare the schema and the histogram-quantile UDF on every boot.

## Quick start

### 1. Generate the JWT secret and the env file

```sh
cp .env.example .env
# Set SIGNOZ_JWT_SECRET in .env to:
openssl rand -hex 32
```

### 2. Fetch the upstream ClickHouse XML configs

This boilerplate intentionally does **not** ship the SigNoz vendor XML
files (license-clean, version-flexible). Pull them from the upstream
repo, matching the `SIGNOZ_VERSION` you pin in `.env`:

```sh
SIGNOZ_REF="${SIGNOZ_VERSION:-v0.120.0}"
git clone --depth 1 --branch "$SIGNOZ_REF" https://github.com/SigNoz/signoz.git /tmp/signoz-src
mkdir -p ./config/clickhouse
cp /tmp/signoz-src/deploy/common/clickhouse/config.xml          ./config/clickhouse/
cp /tmp/signoz-src/deploy/common/clickhouse/users.xml           ./config/clickhouse/
cp /tmp/signoz-src/deploy/common/clickhouse/custom-function.xml ./config/clickhouse/
cp /tmp/signoz-src/deploy/common/clickhouse/cluster.xml         ./config/clickhouse/
cp /tmp/signoz-src/deploy/common/signoz/otel-collector-opamp-config.yaml ./config/
rm -rf /tmp/signoz-src
```

The exact paths in upstream may shift between versions (SigNoz moved
from `deploy/docker/clickhouse-setup/` to `deploy/common/` around
v0.120). If `cp` fails, browse the cloned tree under `/tmp/signoz-src`
and adjust the paths.

### 3. Boot the stack

```sh
docker compose up -d
docker compose ps
```

`init-clickhouse` and `signoz-telemetrystore-migrator` should reach
`Exited (0)` within a minute. The other services should report `healthy`.

Open the UI at `http://127.0.0.1:8080` and complete the first-run wizard.

### 4. Send telemetry

OTel SDKs / collectors / Alloy point at:

- gRPC: `<host>:4317`
- HTTP: `<host>:4318`

Both ports are published on all interfaces by default (configurable via
`OTLP_GRPC_PORT` / `OTLP_HTTP_PORT`). Restrict them at the host firewall
or move the stack to a private network if needed.

## What is configured

| Concern             | Default                                                    |
| ------------------- | ---------------------------------------------------------- |
| Image versions      | Pinned in compose, override via env vars                   |
| Resource limits     | Set on **every** service (clickhouse 2g/2cpu, signoz 512m, ...) |
| Network             | Single bridge `signoz_net`                                 |
| Volumes             | Internal named (no `external: true`)                       |
| UI port             | `127.0.0.1:8080` only                                      |
| OTLP ports          | `0.0.0.0:4317` and `0.0.0.0:4318`                          |
| Healthchecks        | clickhouse, zookeeper, signoz UI                           |
| Log rotation        | 50 MB × 5 files, compressed                                |
| Auth                | JWT signed by `SIGNOZ_JWT_SECRET`                          |
| Retention           | Configured at runtime via the SigNoz UI                    |

## Customising

### Telemetry retention

Set in the SigNoz UI: **Settings → Data Retention** (per signal: traces,
logs, metrics). There are no compose-time TTL knobs for this.

### Resource sizing

The defaults assume a small to medium host. ClickHouse is the heavy
lifter — bump `services.clickhouse.deploy.resources.limits.memory` and
`shared_buffers`-equivalent ClickHouse settings (`max_server_memory_usage`)
in `config/clickhouse/config.xml` for any real ingest volume.

### OTel pipeline

`config/otel-collector-config.yaml` ships the upstream SigNoz default. To
add receivers (e.g. filelog, prometheus, syslog) or processors (e.g.
attributes, filter, transform), edit there and `docker compose up -d
otel-collector` to roll the change.

### Bumping versions

```sh
# In .env
SIGNOZ_VERSION=v0.120.5
SIGNOZ_OTELCOL_VERSION=v0.144.5

docker compose pull signoz signoz-otel-collector
docker compose up -d
# signoz-telemetrystore-migrator runs on boot and applies any new schema migrations
```

When you bump versions you should also re-fetch the matching ClickHouse
XML configs from upstream (see Quick start step 2) — config schema can
shift between minor releases.

## Backups

`scripts/signoz-sqlite-backup.sh` snapshots the `signoz-sqlite` volume
(alert rules, dashboards, users, integrations) as a tarball. Schedule
with cron, systemd timer, or your favourite scheduler:

```sh
# Daily at 03:00, keep 60 days
0 3 * * * BACKUP_DIR=/var/backups/signoz /path/to/signoz/scripts/signoz-sqlite-backup.sh
```

ClickHouse backups are out of scope — the stock approach is
[`clickhouse-backup`](https://github.com/Altinity/clickhouse-backup) or
ClickHouse's native `BACKUP TABLE` to S3-compatible storage. Decide
based on your retention and recovery objectives.

## Security checklist

- [ ] Generated and set `SIGNOZ_JWT_SECRET` (32 random bytes)
- [ ] First-run admin user created with a strong password
- [ ] OTLP ports (4317/4318) restricted to trusted networks (firewall, VPC, VPN)
- [ ] UI port (8080) is loopback only, OR placed behind a trusted reverse proxy
- [ ] Retention policy configured for traces, logs, and metrics
- [ ] `signoz-sqlite` backup scheduled and a restore tested
- [ ] ClickHouse backup strategy decided
- [ ] Bumped resource limits if your ingest volume is more than light

## Troubleshooting

**`SIGNOZ_TOKENIZER_JWT_SECRET` is required**: you forgot step 1 (set it
in `.env` and `docker compose up -d` again).

**ClickHouse won't start, complains about missing config**: you skipped
step 2 (fetch upstream XML files into `config/clickhouse/`).

**`init-clickhouse` keeps restarting**: it downloads a UDF binary from
GitHub releases. Check the host has outbound HTTPS to `github.com`.

**UI loads but shows no data**: confirm the OTel collector is healthy
and you are pointing your apps at the OTLP endpoints, not directly at
SigNoz UI port.

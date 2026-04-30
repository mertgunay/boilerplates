# grafana-lgtm

**Self-hosted Grafana LGTM observability stack** — a single-pane-of-glass
observability stack on Grafana with logs, metrics, traces, and
profiles, all in one Docker Compose file with datasources auto-provisioned:

- **L**oki — logs
- **G**rafana — UI, alerting, dashboards
- **T**empo — traces
- **M**imir — metrics
- **Pyroscope** — continuous profiling (the unofficial "P" of LGTMP)
- **Alloy** — agent that scrapes this host's container logs and node metrics

All in one compose file. Datasources are auto-provisioned so Grafana shows
all four backends connected on first boot.

> Boilerplate / starter. Review every default before running this in
> production. In particular: rotate the admin password, decide whether the
> filesystem-backed retention is enough or you need S3 storage, set up
> backups, and confirm the network exposure matches your context.

## When to pick this over SigNoz

The two stacks (this one and [`compose/signoz`](../signoz)) overlap in
purpose. Pick LGTM when:

- You want Grafana for the UI (vs. SigNoz's bespoke UI).
- You want each signal in a separate, swappable component (Loki / Mimir /
  Tempo / Pyroscope are independent processes; SigNoz puts everything in
  ClickHouse + a single UI).
- You already have S3-compatible object storage and want to point each
  component at it.

Pick SigNoz when:

- You want fewer moving parts and a single backend.
- You want APM-style features (service map, span metrics) baked in
  without configuring Tempo's metrics_generator.

You **cannot** run both on the same host as-is — they both publish on
OTLP ports `:4317` / `:4318`. Pick one, or remap the ports.

## Requirements

- Docker Engine 24+, Docker Compose v2.20+
- ~6 GB RAM headroom (Mimir alone is limited to 2 GB)
- **Linux host required for the Alloy agent.** Alloy mounts `/`, `/proc`
  and `/sys` with `rslave` propagation to read host metrics and the
  Docker socket. Docker Desktop on macOS / Windows runs containers in a
  VM that does not share mount propagation, so the `alloy` service fails
  to start with `path / is mounted on / but it is not a shared or slave
  mount`. The rest of the stack (grafana / loki / tempo / mimir /
  pyroscope) runs fine cross-platform — comment out the `alloy` service
  if you only want the backends on a non-Linux dev box.

### Healthcheck note

Mimir and Pyroscope ship distroless images — no shell, no `wget`/`curl`
inside — so no in-container healthcheck is possible. Dependent services
(`grafana`, `alloy`) wait on `condition: service_started` for those two.
Their `/ready` endpoints stay exposed for external probes.

## Architecture

```
                 ┌──────────────────────────────┐
                 │           Grafana             │ ◀── browser
                 └──────────────┬───────────────┘
                                │ datasources (auto-provisioned)
        ┌─────────────┬─────────┴─────────┬─────────────┐
        ▼             ▼                   ▼             ▼
      Mimir         Loki                Tempo         Pyroscope
        ▲             ▲                   ▲             ▲
        │             │                   │             │
   host metrics  container logs      OTLP gRPC :4317     │
   (Alloy)       (Alloy)             OTLP HTTP :4318     │
                                          │             │
                                       (your apps)  (your apps)
```

## Quick start

### 1. Create the env file

```sh
cp .env.example .env
# Edit .env and set GRAFANA_ADMIN_PASSWORD.
```

### 2. Boot the stack

```sh
docker compose up -d
docker compose ps     # all services should report `healthy` after ~1 minute
```

### 3. Open Grafana

Browser → `http://127.0.0.1:3000`. Log in with the admin user / password
from `.env`. Datasources Mimir / Loki / Tempo / Pyroscope are already
connected — check **Connections → Data sources** to confirm.

### 4. Send telemetry

- **Traces**: point your OTel SDK / collector at this host on `:4317`
  (gRPC) or `:4318` (HTTP).
- **Container logs**: any container running on this host is picked up by
  Alloy automatically (via the Docker socket).
- **Host metrics**: this host's `node_exporter`-style metrics are
  forwarded by Alloy to Mimir — no extra setup.
- **App metrics**: have your app expose Prometheus metrics; add a
  `prometheus.scrape` block to `config/alloy/config.alloy` pointing at
  the app, or push directly to Mimir's `/api/v1/push`.
- **Profiles**: instrument your app with the Pyroscope SDK and point it
  at `http://<host>:4040`.

## What is configured

| Concern             | Default                                                   |
| ------------------- | --------------------------------------------------------- |
| Image versions      | Pinned (Grafana 11.4, Loki 3.3.2, Tempo 2.7, Mimir 2.14, Pyroscope 1.9, Alloy v1.5) |
| Storage             | Filesystem on internal named volumes                      |
| Retention           | 90 days across logs, metrics, traces, profiles            |
| Resource limits     | Set on **every** service (Mimir 2g, Loki/Tempo 1g, ...)   |
| Network             | Single bridge `grafana_lgtm_net`                          |
| Grafana port        | `127.0.0.1:3000` only                                     |
| Tempo OTLP ports    | `0.0.0.0:4317` and `0.0.0.0:4318`                         |
| Healthchecks        | Every service exposes `/ready` or `/api/health`           |
| Provisioning        | Datasources auto-loaded; dashboards folder watches `provisioning/dashboards/*.json` |
| Log rotation        | 50 MB × 5 files, compressed                               |

## Customising

### Add dashboards

Drop `*.json` files into `provisioning/dashboards/`. Grafana picks them
up within 10 minutes (configurable via `updateIntervalSeconds` in
`provisioning/dashboards/dashboards.yml`). Files in subdirectories show
up as nested folders in the UI.

Useful starter dashboards from grafana.com:

- Node Exporter Full (ID `1860`) — host metrics
- Loki Stack (ID `13639`) — log volumes
- Tempo (ID `17602`) — trace stats

### Switch to S3-compatible storage

Filesystem storage is fine for a single node and light load. For
anything more, point each component at S3-compatible object storage:

- `config/loki/config.yaml` → `storage_config.aws` and
  `schema_config.configs[].object_store: s3`
- `config/mimir/config.yaml` → `blocks_storage.backend: s3` plus
  `blocks_storage.s3` block
- `config/tempo/config.yaml` → `storage.trace.backend: s3` plus
  `storage.trace.s3` block
- `config/pyroscope/config.yaml` → `storage.backend: s3` plus
  `storage.s3` block

Add the credentials via env vars referenced in each config.

### Bumping versions

Edit the image tag in `compose.yml`, then:

```sh
docker compose pull <service>
docker compose up -d <service>
```

Grafana, Loki, Mimir, Tempo and Pyroscope all support online upgrades
within a minor version. For major version jumps, read the upstream
release notes — config schema occasionally shifts.

### Disable Alloy

If you don't want this host's metrics or container logs picked up,
comment out the `alloy` service in `compose.yml`. The rest of the stack
works without it (you'll just need to push your own data to Loki and
Mimir from elsewhere).

## Backups

Not included. Two reasonable approaches:

1. **Volume snapshots** — snapshot `grafana-data`, `loki-data`,
   `tempo-data`, `mimir-data`, `pyroscope-data` at the storage layer.
   Loki and Tempo are append-only, so consistent snapshots are
   relatively forgiving; Mimir's TSDB needs a clean stop or a careful
   filesystem snapshot.
2. **Object storage with versioning** — switch to S3 storage (above),
   enable bucket versioning + lifecycle policies, and let your storage
   provider handle durability.

For Grafana state (dashboards, alerts, datasource overrides), back up
the `grafana-data` volume — same pattern as the SigNoz `signoz-sqlite`
backup script. Adapt
[`../signoz/scripts/signoz-sqlite-backup.sh`](../signoz/scripts/signoz-sqlite-backup.sh)
by changing `VOLUME_NAME=grafana-data`.

## Security checklist

- [ ] `GRAFANA_ADMIN_PASSWORD` is strong and stored outside the repo
- [ ] First-run admin user created (or admin password changed in UI on first login)
- [ ] OTLP ports (4317/4318) restricted to trusted networks
- [ ] Grafana port (3000) is loopback only OR placed behind a trusted reverse proxy
- [ ] Reviewed Alloy's `/var/run/docker.sock` mount — it grants this
      container the ability to enumerate every container on the host
- [ ] Decided on retention vs. storage cost (90d filesystem may be a lot
      of disk; bump up or down)
- [ ] Backup strategy chosen (volume snapshots or S3 with versioning)

## Troubleshooting

**`GRAFANA_ADMIN_PASSWORD` is required**: you forgot to set it in `.env`.

**Datasource health checks fail in Grafana**: confirm all four backends
report `healthy` (`docker compose ps`). The compose file makes Grafana
wait on them via `depends_on: condition: service_healthy`, so a startup
failure usually means a config typo — `docker compose logs <service>`
will say which one.

**Alloy reports zero host metrics on macOS**: see the requirements
section. The `rslave` mount propagation is Linux-specific.

**Disk fills up unexpectedly**: 90-day retention across four data
backends adds up. Check sizes with `docker system df -v` and adjust
retention in each component's config.

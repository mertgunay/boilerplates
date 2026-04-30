# prometheus

**Self-hosted Prometheus + node-exporter + cAdvisor** — a production-leaning
host-monitoring stack with 30-day TSDB retention:

- **prometheus** — TSDB + UI + scrape engine
- **node-exporter** — host-level metrics (CPU, memory, disk, network, ...)
- **cAdvisor** — per-container metrics (CPU, memory, fs, network)

Prometheus scrapes both exporters out of the box (see `prometheus.yml`).
Add more scrape jobs there for your own apps.

> Boilerplate / starter. Review every default before running this in
> production. In particular: decide on a retention/storage strategy,
> add alerting (this stack ships no Alertmanager), and confirm the
> network exposure matches your context.

## Requirements

- Docker Engine 24+, Docker Compose v2.20+
- **Linux host required for the full stack.** node-exporter and cAdvisor
  mount the root filesystem with `rslave` propagation. Docker Desktop on
  macOS / Windows runs containers inside a VM that does not share mount
  propagation with the host, so both containers fail to start with
  `path / is mounted on / but it is not a shared or slave mount`. The
  `prometheus` service itself runs fine cross-platform — comment out the
  `node-exporter` and `cadvisor` services if you only want the TSDB + UI
  on a non-Linux dev box.

## Quick start

```sh
cp .env.example .env          # optional — only needed for remote_write
docker compose up -d
docker compose ps             # all three should report `healthy`
```

Open the UIs:

- Prometheus: http://127.0.0.1:9090
- cAdvisor:   http://127.0.0.1:8080

Try a query in Prometheus: `up` — should return `1` for `prometheus`,
`node`, and `cadvisor`.

## What is configured

| Concern         | Default                                                    |
| --------------- | ---------------------------------------------------------- |
| Prometheus      | `v2.55.0`, 30 day TSDB retention                           |
| node-exporter   | `v1.8.2`, host fs/proc/sys mounted read-only               |
| cAdvisor        | `v0.50.0`, privileged (required for kernel stats)          |
| UI ports        | Prometheus on `127.0.0.1:9090`, cAdvisor on `127.0.0.1:8080` |
| Network         | Single bridge `prometheus_net`                             |
| Hot reload      | `--web.enable-lifecycle` is on — `curl -XPOST /-/reload`   |
| Healthchecks    | `/-/healthy`, `/healthz`, and a `/metrics` GET             |
| Resource limits | Prometheus 1g, cAdvisor 256m, node-exporter 128m           |
| Log rotation    | 50 MB × 5 files, compressed                                |

## Customising

### Add scrape jobs

Edit `prometheus.yml` and either restart the container or hot-reload:

```sh
curl -XPOST http://127.0.0.1:9090/-/reload
```

For container DNS to resolve, the target must be on the same Docker
network. To scrape an app outside this stack, use `host.docker.internal`
(Docker Desktop) or the host's LAN IP.

### Add alerting rules

1. Create a `rules/` directory next to `compose.yml`.
2. Mount it: add `- ./rules:/etc/prometheus/rules:ro` to
   `services.prometheus.volumes`.
3. Uncomment the `rule_files:` section in `prometheus.yml`.
4. To actually fire alerts you also need an Alertmanager — add it as a
   service or point at an existing one via `alerting.alertmanagers` in
   `prometheus.yml`.

### Long-term storage

Local TSDB on a single node is fine up to maybe a million samples per
second. Beyond that, push to a long-term store via `remote_write`:

- [Thanos](https://thanos.io) — Prometheus-native, deduplication and global query
- [Cortex / Mimir](https://grafana.com/oss/mimir/) — multi-tenant, horizontal scale
- [VictoriaMetrics](https://victoriametrics.com) — single-binary, fast, MIT
- [Grafana Cloud](https://grafana.com/products/cloud/) — managed remote write target

`prometheus.yml` includes a commented `remote_write` block driven by env
vars in `.env`.

### Bumping versions

Edit the image tags in `compose.yml`, then:

```sh
docker compose pull prometheus node-exporter cadvisor
docker compose up -d
```

cAdvisor releases break privileged-mount expectations from time to time —
read the upstream changelog before a major bump.

## Security checklist

- [ ] Decided whether the loopback-only port bindings are correct
      (LAN scrape? Reverse proxy in front of the UI?)
- [ ] Reviewed cAdvisor's `privileged: true` and the host mounts —
      this is a high-trust container
- [ ] Reviewed node-exporter's host mounts (`/proc`, `/sys`, `/`)
- [ ] Set TSDB retention against your disk budget (30 days × scrape volume)
- [ ] Decided on alerting (Alertmanager + receivers) before relying on this for ops
- [ ] If using `remote_write`, credentials live outside the repo

## Troubleshooting

**`up` is `0` for `node` or `cadvisor`**: container DNS only works on
the same network. Confirm `docker compose ps` shows both on the
`prometheus_net` network and that the targets in `prometheus.yml` use
the service names, not `localhost`.

**cAdvisor fails to start**: the `privileged: true` and `/dev/kmsg`
device are required for host kernel statistics. Some hardened hosts
disallow this — drop cAdvisor and lose container-level metrics, or use
[`docker_sd_config`](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#docker_sd_config)
to scrape per-container `/metrics` endpoints directly.

**Disk fills up**: 30 days × dense scrapes adds up fast. Check actual
size with `docker system df -v` and adjust
`--storage.tsdb.retention.time` (or set `--storage.tsdb.retention.size`
for a hard cap).

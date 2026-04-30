# boilerplates

A small, opinionated collection of Docker Compose stacks for things you
end up self-hosting often. Each stack starts from an upstream / vendor
default and adds the production-leaning details that turn a quickstart
into something you'd actually run on a fleet.

The bar for what lives here:

- **Pinned image versions.** No `:latest`. You should be able to come
  back in a year and `docker compose up -d` still does the same thing.
- **Healthchecks on every service.** So `depends_on:
  condition: service_healthy` actually means something.
- **Resource limits on every service.** So a runaway process can't take
  the host down with it.
- **Defensive port bindings.** Admin / debug interfaces published on
  `127.0.0.1` only by default; ports that have to be public say so.
- **Secrets via `.env`, never in the repo.** Every stack ships a
  `.env.example` with placeholder values. Real values fail loudly when
  missing (`${VAR:?...}` pattern).
- **Per-stack README.** Quick start, customising knobs, backup story,
  security checklist, the most common troubleshooting scenarios.

## Stacks

| Stack | Purpose |
| --- | --- |
| [`compose/postgres`](compose/postgres) | PostgreSQL with file-based Docker secrets, scram-sha-256, healthcheck, log rotation |
| [`compose/postgres-tr`](compose/postgres-tr) | Same as above with `tr_TR.UTF-8` baked in via a custom image |
| [`compose/redis`](compose/redis) | Redis with mandatory password, AOF persistence, eviction-policy guidance |
| [`compose/nginx`](compose/nginx) | Standalone hardened nginx (read-only fs, dropped caps) for config-as-code reverse proxying |
| [`compose/nginxproxymanager`](compose/nginxproxymanager) | Nginx Proxy Manager + MariaDB on a split network — graphical reverse proxy and Let's Encrypt automation |
| [`compose/selenium-grid`](compose/selenium-grid) | Selenium Grid 4 — hub + Chrome node, scalable, with optional VNC |
| [`compose/prometheus`](compose/prometheus) | Prometheus + node-exporter + cAdvisor — host monitoring with 30-day retention |
| [`compose/signoz`](compose/signoz) | SigNoz minimal core — single-pane-of-glass observability on ClickHouse |
| [`compose/signoz-with-nginx`](compose/signoz-with-nginx) | SigNoz with a hardened nginx reverse proxy in front (rate limiting, security headers, JSON access log) |
| [`compose/grafana-lgtm`](compose/grafana-lgtm) | Grafana LGTM — Loki + Grafana + Tempo + Mimir + Pyroscope + Alloy in one compose, datasources auto-provisioned |

## Using a stack

```sh
git clone https://github.com/mertgunay/boilerplates.git
cd boilerplates/compose/<stack>

cp .env.example .env          # if the stack ships one
$EDITOR .env                  # set real values

docker compose up -d
docker compose ps             # confirm `healthy`
cat README.md                 # for everything else
```

Each stack is independent — you can copy a single directory into your
own infra repo and treat it as a starting point. The conventions are
documented per-stack so you don't have to take the whole repo to use
one piece.

## Conventions

These show up in every stack and the per-stack READMEs assume them:

- **`x-logging-default` anchor** — 50 MB × 5 files, gzip. Limits Docker
  log driver disk usage.
- **`${VAR:?message}`** — used for required secrets so a missing value
  produces a clear error at compose-validation time, not a confusing
  runtime crash.
- **Loopback ports** — admin / debug UIs default to `127.0.0.1:<port>`.
  Override via env var (`ADMIN_PORT=...`) or rebind in compose.yml when
  you want LAN exposure.
- **Internal networks** — where one service is the only legitimate
  client of another (NPM ↔ its MariaDB), the dependency runs on a
  `internal: true` network so the database has no route off the bridge.
- **Named volumes, not `external: true`** — fresh deployments should
  not depend on pre-existing volumes. Migrate explicitly when porting
  data from another setup.

## Contributing

Pull requests welcome. The expectations:

- Match the conventions above. New stacks must ship a README, an
  `.env.example`, healthchecks, resource limits, and pinned versions.
- Keep stacks **standalone**. No shared base images, no implicit
  dependencies between stack directories.
- No real secrets, hostnames, or internal infrastructure references in
  configs or comments. Use placeholders (`changeme`, `your-host.example`).
- Comments and docs in English.

## License

[MIT](LICENSE).

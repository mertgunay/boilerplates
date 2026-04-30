# homelab

[![License: MIT](https://img.shields.io/github/license/mertgunay/homelab)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/mertgunay/homelab?display_name=tag&sort=semver)](https://github.com/mertgunay/homelab/releases)
[![Last commit](https://img.shields.io/github/last-commit/mertgunay/homelab)](https://github.com/mertgunay/homelab/commits/main)
[![Open issues](https://img.shields.io/github/issues/mertgunay/homelab)](https://github.com/mertgunay/homelab/issues)

**Production-leaning Docker Compose stacks for self-hosting** — Postgres,
Redis, nginx, Nginx Proxy Manager, Selenium Grid, Prometheus, SigNoz,
Grafana LGTM, Teleport, and friends. Each stack starts from the
upstream / vendor default and layers on the operational details that
turn a quickstart into something you'd actually run on a fleet:
pinned versions, healthchecks on every service, fail-loud secrets,
defensive port bindings, hardened nginx defaults.

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
  `.env.example` with required keys left **blank** and optional keys
  commented out. Required values are validated at compose start-up via
  the `${VAR:?...}` pattern — running `docker compose up` against a
  blank `.env` fails loudly instead of silently shipping a default
  password.
- **Per-stack README.** Quick start, customising knobs, backup story,
  security checklist, the most common troubleshooting scenarios.

## Stacks

Pick the row that matches what you're trying to self-host. Every
stack is independent — copy a single directory into your own infra
repo and treat it as a starting point.

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
| [`compose/teleport`](compose/teleport) | Teleport CE — single-node identity-based access (SSH, Kubernetes, db, web app proxy) with WebAuthn MFA and TLS routing on `:443` |

## Using a stack

```sh
git clone https://github.com/mertgunay/homelab.git
cd homelab/compose/<stack>

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

### Running multiple stacks on the same host

Defaults assume a stack has the host to itself. Common collisions when
you stack them up:

- **Ports.** `postgres` and `postgres-tr` both default to `5432`;
  `signoz` and `grafana-lgtm` both bind the OTLP ports `4317/4318`;
  `nginx`, `nginxproxymanager`, `signoz-with-nginx` and `teleport` all
  want `:80` / `:443`. Override the published port via the env vars
  documented in each `.env.example`.
- **Container names.** Stacks set explicit `container_name:` for
  ergonomics. If two stacks would land on the same name, set
  `COMPOSE_PROJECT_NAME` per stack — Docker prefixes it onto resources
  and avoids the collision.
- **Compose networks.** Each stack creates its own bridge network — no
  cross-stack collisions there. To wire a service from stack A to
  stack B, attach an `external: true` network in both compose files.

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
  configs or comments. Use placeholders (`your-host.example`,
  `your-cluster`) for documented examples; for required `.env` keys
  leave the value blank so `${VAR:?}` fails loudly instead of letting
  a `changeme`-style default reach production.
- Comments and docs in English.

## License

[MIT](LICENSE).

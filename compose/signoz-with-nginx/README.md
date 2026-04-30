# signoz-with-nginx

**Self-hosted [SigNoz](https://signoz.io) behind a hardened nginx
reverse proxy** — rate limiting, security headers, JSON access log,
gzip, and a clear seam to add TLS. Same core as
[`compose/signoz`](../signoz/README.md) (clickhouse + zookeeper +
signoz UI + otel-collector + migrators) — see that README for
setup, backup, version bumps, and the full security checklist.

> Boilerplate / starter. Same disclaimers as the minimal core apply.

## When to use this

Pick this variant if you want SigNoz exposed beyond the host loopback
and you want:

- nginx hardening: read-only filesystem, dropped Linux capabilities,
  tmpfs mounts for the writeable paths nginx needs
- Per-location rate limiting (login is strict, websocket is
  unrestricted with a 24h read timeout)
- A JSON access log, baseline security headers, gzip
- A clear seam to add TLS or auth on top

If you only need local-host access, prefer the minimal
[`compose/signoz`](../signoz) and reach the UI on `127.0.0.1:8080`.

## What is different from the minimal core

| Aspect                | Minimal core                       | This variant                                  |
| --------------------- | ---------------------------------- | --------------------------------------------- |
| UI port published     | `127.0.0.1:8080` (loopback)        | not published — nginx fronts it               |
| nginx                 | absent                             | hardened (`read_only`, `cap_drop: ALL`, tmpfs) |
| Public listen         | n/a                                | `${NGINX_PORT:-80}` on all interfaces         |
| Rate limiting         | n/a                                | login 5 r/s, API 60 r/s, websocket unbounded  |
| Access log            | none (Docker logs only)            | nginx JSON access log                         |
| Security headers      | n/a                                | X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy |

Everything else (resource limits, healthchecks, OTLP ports, volume
layout, backup script) follows the minimal core.

## Quick start

The setup is the same as [`compose/signoz`](../signoz/README.md), with
two extras:

1. Run **both** Quick-start steps from the core README (env file +
   ClickHouse XML configs from upstream).
2. `docker compose up -d --build` the first time so the nginx image gets built.

Then reach the UI at `http://<host>:${NGINX_PORT:-80}`.

## TLS

This stack does **not** terminate TLS. Three reasonable approaches:

1. **Network boundary terminates** — sit the stack inside a VPN or a
   private subnet and let an upstream gateway / WAF / load balancer
   handle TLS.
2. **Terminate in nginx** — drop a certificate into the image build
   context and add a `listen 443 ssl;` server block to `nginx.conf`.
   You will need to add a volume mount or build-time COPY for the cert.
3. **Add a sidecar terminator** — Caddy / Traefik / Cloudflare Tunnel /
   stunnel in front of nginx. The nginx config here continues to serve
   plain HTTP on the internal network.

Pick whichever matches your existing infrastructure. There is no
"right" default for a boilerplate.

## Customising the nginx config

`nginx/nginx.conf` is what gets baked into the image at build time. To
change rate limits, add a server_name match, add CSP, etc., edit there
and rebuild:

```sh
docker compose up -d --build nginx
```

Note on CSP: SigNoz embeds third-party SDKs (Pylon, Appcues, etc.). A
strict `Content-Security-Policy` without explicit allowlists for those
will break the UI in subtle ways (silent failures, broken in-app help).
Add CSP intentionally if you need it.

## Security checklist (extends the core checklist)

- [ ] Decided on TLS termination strategy
- [ ] `NGINX_PORT` exposure scoped correctly (LAN, VPN-only, public + WAF, etc.)
- [ ] Rate limit numbers reviewed against your expected traffic patterns
- [ ] `server_name` set explicitly if you serve multiple hosts

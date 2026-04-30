# nginx

**Self-hosted hardened nginx** — read-only filesystem, dropped Linux
capabilities, tmpfs mounts for the writeable paths nginx actually
needs. Use as a reverse proxy, static server, or load balancer; drop
server blocks into `./conf.d/` and static files into `./html/`.

> Boilerplate / starter. Sensible hardening defaults but no opinions
> about what you serve. Drop your own server blocks into `conf.d/` and
> static files into `html/`.

## When to use this vs. nginxproxymanager

- **`compose/nginx`** — write nginx config yourself, deploy as code.
  No database, no UI. Best when nginx config lives in version control.
- **`compose/nginxproxymanager`** — graphical UI for proxy hosts and
  Let's Encrypt automation. Persists state in MariaDB. Best when
  non-engineers will manage hosts.

## Quick start

```sh
cp .env.example .env          # optional — only if you want non-default ports
docker compose up -d
docker compose ps             # nginx should report `healthy`
curl http://127.0.0.1/        # serves ./html/index.html
curl http://127.0.0.1/health  # returns "ok"
```

## What is configured

| Concern             | Default                                                  |
| ------------------- | -------------------------------------------------------- |
| Image               | `nginx:1.27-alpine`, version-pinned                      |
| Hardening           | `read_only: true`, `cap_drop: ALL` + minimal `cap_add`   |
| Writeable paths     | tmpfs: `/var/cache/nginx`, `/var/run`, `/var/log/nginx`, `/tmp` |
| Ports               | `:80` and `:443` on all interfaces                       |
| Config bind-mount   | `./conf.d → /etc/nginx/conf.d:ro`                        |
| Content bind-mount  | `./html → /usr/share/nginx/html:ro`                      |
| Cert bind-mount     | `./certs → /etc/nginx/certs:ro`                          |
| Healthcheck         | `/health` returns 200                                    |
| Resource limits     | 256 MB / 0.25 CPU                                        |
| Log rotation        | 50 MB × 5 files, compressed (Docker logs only — nginx access log goes to tmpfs) |

## Customising

### Add a reverse proxy

Edit `conf.d/default.conf` (the file ships with a commented template).
Reload without restarting:

```sh
docker compose exec nginx nginx -s reload
```

Or restart:

```sh
docker compose restart nginx
```

To reach upstream services running in **other** compose stacks, attach
them to the `nginx_net` network. Easiest way: in the upstream stack's
compose.yml, add the network as external:

```yaml
networks:
  default:
    name: <upstream-stack-name>_net
  nginx_net:
    external: true
    name: nginx_net
```

…and add `networks: [default, nginx_net]` to the service. Then in the
nginx config, use the upstream's container name:
`proxy_pass http://my-app:8000;`.

### Add TLS

1. Drop your fullchain + privkey into `./certs/<domain>/`. Common
   tools that produce these:
   - `certbot --standalone` on the host (need to stop nginx for the
     duration of the renewal — port 80 conflict)
   - [`acme.sh`](https://acme.sh) which runs in a sidecar
   - A cert from your own CA / cloud provider
2. Uncomment the TLS server block in `conf.d/default.conf` and set the
   right paths.
3. Reload: `docker compose exec nginx nginx -s reload`.

For automatic Let's Encrypt issuance and renewal, NPM
([`compose/nginxproxymanager`](../nginxproxymanager)) handles that for
you — pick that stack instead if you don't want to operate ACME yourself.

### Logging

The container's tmpfs holds `/var/log/nginx/access.log` and
`error.log`. They survive only as long as the container does. To
persist them or ship them somewhere:

- Add a real volume mount (replace `tmpfs: ["/var/log/nginx"]` with a
  named volume mount) — but you lose the read-only hardening on that path.
- Send logs to stdout (already on by default in the upstream image's
  `nginx.conf`) and let the Docker log driver / Alloy / Promtail
  collect them.

The default config in this stack uses the upstream pattern — `access_log off`
on `/health` only, otherwise upstream defaults route to stdout.

### Bumping versions

Edit the image tag in `compose.yml`, then:

```sh
docker compose pull
docker compose up -d
```

Watch upstream nginx [security advisories](https://nginx.org/en/security_advisories.html)
and bump the patch version when relevant.

## Security checklist

- [ ] Decided whether `:80` / `:443` should be on all interfaces or
      restricted (firewall, VPN-only)
- [ ] If serving TLS, certs are not committed to the repo (`./certs`
      should be gitignored at the application repo level)
- [ ] If reverse-proxying, upstream containers are on a Docker network
      they share with nginx — not exposed on the host
- [ ] Reviewed `cap_add` — only NET_BIND_SERVICE, CHOWN, SETUID, SETGID
      remain (needed for `:80` bind and dropping privileges)
- [ ] If you mounted `/var/log/nginx` to a real volume, ensure log
      rotation is configured at the volume host level (the in-container
      tmpfs mount has no rotation configured because it is recreated
      on each restart)

## Troubleshooting

**nginx fails to start with `[emerg] open() "/var/log/nginx/access.log" failed`**:
the upstream image's nginx.conf expects `/var/log/nginx` to be writeable.
The tmpfs mount provides this — confirm it's still in `compose.yml` if
you customised the file.

**`502 Bad Gateway` on a proxy_pass**: nginx can't resolve the upstream.
Container DNS only works on a network you share — see "Add a reverse
proxy" above.

**TLS handshake fails after dropping in a cert**: `nginx -t` first to
validate config (`docker compose exec nginx nginx -t`), and confirm
the cert + key paths in your config match the bind-mount layout.

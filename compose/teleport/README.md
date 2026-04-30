# teleport

Self-hosted [Teleport Community Edition](https://goteleport.com) —
identity-based access for SSH, Kubernetes, databases, and internal web
apps. This stack runs auth + proxy + ssh in a single container, which is
the right shape for a small fleet or homelab.

> Boilerplate / starter. Teleport is identity infrastructure — when it
> goes down, you can't reach anything that depends on it. Read the
> "Break-glass" section before pointing your first production host at it.

## When to use this

Use Teleport when you want any of:

- **Short-lived SSH certificates** instead of long-lived `authorized_keys`.
- **Audit trail and session recording** across every server.
- **MFA on every login** (WebAuthn / TOTP), enforced centrally.
- **A web UI** for terminal access without a local SSH client.
- **Database / Kubernetes / web app proxy** under the same auth surface.

If you just want a bastion host or a JIT SSH proxy, this is heavier than
you need. If you want a paranoid kill-switch on a fleet of 5+ servers,
this is exactly the right shape.

## Requirements

- Docker Engine 24+, Docker Compose v2.20+
- A DNS record for whatever hostname you pick as `proxy.public_addrs`.
- A way to get a TLS cert for that hostname — either ACME (this stack
  supports HTTP-01 inline; DNS-01 / wildcard certs via BYO) or your own.
- Outbound HTTPS for the container to fetch the latest version metadata
  (Teleport phones home for upgrade hints unless you disable it).

## Quick start

### 1. Edit `config/teleport.yaml`

Three values must be set before first boot. They are immutable after
the cluster initializes:

```yaml
auth_service:
  cluster_name: <your-cluster-name>     # lowercase, no spaces

proxy_service:
  public_addrs: ["<your-host>.<your-domain>:443"]

auth_service:
  authentication:
    webauthn:
      rp_id: <your-host>.<your-domain>  # match the host portion above
```

Pick exactly one TLS strategy and uncomment the matching block:

- **ACME (HTTP-01)** — easiest if the host serves HTTP/HTTPS publicly.
  Set `acme.email` to a real address.
- **BYO certificate** — drop `fullchain.pem` + `privkey.pem` into
  `./certs/` (a `.gitkeep` is there to anchor the directory) and
  reference them under `https_keypairs`.

### 2. Mirror the values in `.env`

```sh
cp .env.example .env
# Set TELEPORT_CLUSTER_NAME and TELEPORT_PROXY_PUBLIC_ADDR
# to the same values you used in config/teleport.yaml.
```

The env vars are not actually read by Teleport — they are convenience
references so future-you can find the cluster name without hunting
through the YAML.

### 3. Boot the stack

```sh
docker compose up -d
docker compose logs -f teleport       # watch for "Starting Teleport"
docker compose ps                     # service should report `healthy` after ~30s
```

Open the proxy UI at `https://<your-host>.<your-domain>` and finish the
first-run wizard.

### 4. Create your first user

There is no default user. Create one via `tctl` running inside the container:

```sh
docker compose exec teleport tctl users add mert --roles=editor,access,auditor
```

The command prints a one-time signup URL. Open it in a browser, set a
password, and register an MFA factor (WebAuthn / Touch ID / TOTP).

### 5. Connect your first server

On the target host (not this one), install the Teleport agent and join
the cluster with a one-time token:

```sh
# On this host:
docker compose exec teleport tctl tokens add --type=node --ttl=1h

# On the target host (Linux):
curl https://goteleport.com/static/install.sh | bash -s 18.7.2
sudo teleport configure --proxy=<your-host>.<your-domain>:443 --token=<TOKEN_FROM_PREVIOUS_STEP> | sudo tee /etc/teleport.yaml
sudo systemctl enable --now teleport
```

The host should show up in the Teleport UI within ~10 seconds.

Then from your laptop:

```sh
tsh login --proxy=<your-host>.<your-domain>:443
tsh ssh root@<target-host-name>
```

## What is configured

| Concern             | Default                                                    |
| ------------------- | ---------------------------------------------------------- |
| Image               | `public.ecr.aws/gravitational/teleport:18.7.2` (CE)        |
| Services in process | Auth + Proxy + SSH                                         |
| Storage             | Local SQLite (in `teleport-data` named volume)             |
| TLS routing         | Enabled — every protocol multiplexed on `:443`             |
| Public ports        | `:443` only (override via `TELEPORT_PROXY_PORT`)           |
| Auth methods        | Local user/pass + WebAuthn MFA                             |
| Audit log           | JSON to stderr (Docker log driver picks it up)             |
| Resource limits     | 1 GB / 1 CPU                                               |
| Healthcheck         | `https://localhost/healthz` (insecure-skip — self-loopback) |
| Log rotation        | 50 MB × 5 files, compressed                                |

## Customising

### Web UI behind a private network

Teleport works fine with a private-only proxy. Two patterns:

1. **DNS-01 cert + private IP** — issue the cert via DNS-01 (no public
   port 80 needed), point public DNS at a private IP, only WireGuard /
   VPN clients can resolve / route. Drop the cert in `./certs/` and use
   the BYO keypair section.
2. **External terminator** — terminate TLS at an upstream gateway and
   forward plain HTTP / HTTPS to this stack. Disable Teleport's own TLS
   handling. Out of scope here; the Teleport docs cover this under
   "Reverse Proxying".

### Bumping the version

```sh
# In .env: bump TELEPORT_VERSION
docker compose pull
docker compose up -d
```

Teleport supports rolling upgrades within a major version. For major
jumps (17.x → 18.x), read the upstream
[upgrade guide](https://goteleport.com/docs/upgrading/) — schema
migrations sometimes need a one-shot `tctl` command.

### Adding more roles / users

Edit roles via the UI or `tctl`:

```sh
docker compose exec teleport tctl get roles
docker compose exec teleport tctl edit role/access
docker compose exec teleport tctl users add jane --roles=access
```

For automation (CI runners, backup jobs), use **Machine ID (`tbot`)** —
short-lived bot certificates instead of static keys. Out of scope for
this README; see the Teleport docs.

## Backups

The whole cluster state lives in `teleport-data`. Two reasonable
approaches:

1. **Volume tarball + offsite copy** — adapt
   [`../signoz/scripts/signoz-sqlite-backup.sh`](../signoz/scripts/signoz-sqlite-backup.sh)
   with `VOLUME_NAME=teleport-data`. SQLite needs a clean stop or a
   `BEGIN IMMEDIATE` snapshot for a consistent dump; tarballing the
   whole volume while Teleport is running may produce a slightly
   inconsistent file. Stop with `docker compose stop teleport` for a
   clean snapshot, copy, and start again.
2. **External backend** — for any meaningful deployment, switch from
   SQLite to a network-backed storage backend (etcd, DynamoDB,
   Firestore). The upstream `teleport.storage` docs cover the swap.

Whichever you pick, **test the restore** on a fresh host before
relying on it. Teleport recovery without a working backup is painful.

## Break-glass

If Teleport is down, you cannot reach hosts that depend on it. Plan
for this **before** you cut over:

- Keep `~/.ssh/authorized_keys` populated on every host you onboard
  for some "shadow period" (running Teleport in parallel before
  flipping off legacy SSH).
- Keep a strong local root password on every host, stored in your
  password manager.
- For the host running this stack: keep console access (ESXi,
  KVM, IPMI, hypervisor web UI) — that bypasses both Teleport and SSH.
- Periodically test that you can recover from each fallback.

If Teleport itself crashes:

```sh
docker compose logs --tail=200 teleport
docker compose restart teleport
```

If the cluster state is corrupt, restore from backup (above).

## Security checklist

- [ ] `cluster_name`, `public_addrs`, `webauthn.rp_id` set in
      `config/teleport.yaml` (these are immutable!)
- [ ] TLS strategy picked and tested (ACME or BYO)
- [ ] First admin user created with a strong password and MFA registered
- [ ] WebAuthn / MFA enforced for all roles (the default `editor`,
      `access`, `auditor` roles already require it)
- [ ] Backup of `teleport-data` scheduled and restore tested
- [ ] Break-glass paths confirmed (legacy SSH still works during the
      shadow period; console access available)
- [ ] If running behind a private network, the host is **not** reachable
      from the public internet (no port 443 ingress except via VPN /
      bastion / private LB)
- [ ] Audit log destination decided — stderr to Docker logs is fine for
      a homelab, ship to SIEM / SigNoz / Loki for any production deployment

## Troubleshooting

**`crypto/tls: bad certificate` from `tsh`**: certificate hostname
mismatch. Either the cert was issued for a different name, or
`proxy_service.public_addrs` doesn't match what you're connecting to.

**Healthcheck stays unhealthy**: the container's `curl` only knows
about the self-signed cert during the first ~30 seconds before ACME
issues. After ACME completes, the healthcheck flips to healthy.

**`ERROR: cluster_name has been set already`**: you tried to change
`cluster_name` after first boot. Either revert to the original or wipe
the `teleport-data` volume to start a new cluster (destructive!).

**`tctl users add` succeeds but no signup link prints**: the proxy
isn't reachable at `public_addrs` from the user's machine. Check DNS,
firewall, and that the host actually resolves the proxy hostname.

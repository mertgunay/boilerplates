# selenium-grid

[Selenium Grid 4](https://www.selenium.dev/documentation/grid/) — hub +
one Chrome node out of the box, with commented templates for Firefox
and Edge nodes.

> Boilerplate / starter. Selenium nodes load arbitrary user-controlled
> URLs by design — keep the hub off the public internet.

## Requirements

- Docker Engine 24+, Docker Compose v2.20+
- ~3 GB RAM headroom per browser node (the limit is set to 2 GB, plus
  shm_size of 2 GB)
- **linux/amd64 host.** Upstream `selenium/node-chrome` (and Edge) ship
  amd64-only — Google does not publish a stable linux/arm64 Chrome
  build. On Apple Silicon, `up -d` fails with `no matching manifest for
  linux/arm64/v8`. Either run the stack on an x86_64 VM (the production
  target) or add `platform: linux/amd64` to each node service to force
  Rosetta translation for casual local testing.

## Quick start

```sh
cp .env.example .env          # optional — only needed for tuning / VNC
docker compose up -d
docker compose ps             # hub + chrome should report `healthy`
open http://127.0.0.1:4444    # Grid UI
```

Point your test runner at `http://127.0.0.1:4444/wd/hub` (Selenium 3 API)
or `http://127.0.0.1:4444` (Selenium 4 W3C API). Example with Python:

```python
from selenium import webdriver
from selenium.webdriver.chrome.options import Options

opts = Options()
driver = webdriver.Remote(
    command_executor="http://127.0.0.1:4444",
    options=opts,
)
driver.get("https://example.com")
driver.quit()
```

## What is configured

| Concern                  | Default                                                  |
| ------------------------ | -------------------------------------------------------- |
| Hub image                | `selenium/hub:4.27.0`                                    |
| Chrome node              | `selenium/node-chrome:4.27.0`                            |
| Hub UI port              | `127.0.0.1:4444`                                         |
| Event bus ports          | Internal only (4442/4443 not published to host)          |
| Sessions per node        | 8 (`SE_NODE_MAX_SESSIONS`)                               |
| Session timeout          | 300 s                                                    |
| `shm_size` per node      | 2 GB (Chromium requires this — do not lower)             |
| VNC                      | Off (commented template in compose.yml to enable)        |
| Healthchecks             | Both hub and node expose `/status`                       |
| Resource limits          | Hub 512m, each node 2g                                   |
| Log rotation             | 50 MB × 5 files, compressed                              |

## Customising

### Run multiple Chrome instances

```sh
docker compose up -d --scale chrome=4
```

The hub will distribute sessions across all four. Don't put a
`container_name:` on the `chrome` service — it would prevent scaling.

### Add Firefox or Edge

Uncomment the matching service block in `compose.yml`. Each browser
service inherits from the `x-node-defaults` anchor (shm_size, healthcheck,
resource limits, depends_on, env vars), so the only thing you specify is
the image. Edge is `linux/amd64` only — set `platform: linux/amd64` on
Apple Silicon if you really need it (will run under emulation, slow).

### Enable VNC for debugging

Uncomment the VNC environment variables in the `chrome` service in
`compose.yml`, set `SE_VNC_PASSWORD` in `.env`, and rebuild:

```sh
docker compose up -d chrome
```

Selenium nodes ship with [noVNC](https://novnc.com), so you can open
the browser-side VNC at:

```
http://<node-ip>:7900
```

You'll need to either publish port 7900 (add `ports: ["127.0.0.1:7900:7900"]`)
or tunnel to it. Don't expose VNC on a public interface without a strong
password.

### Bumping versions

```sh
# In compose.yml: bump the image tags
docker compose pull
docker compose up -d
```

The Selenium project tags both `:X.Y.Z` and date-suffixed `:X.Y.Z-YYYYMMDD`
images. The boilerplate uses the plain semver tag for predictability;
switch to the date-suffixed tag if you need to pin to a specific build.

## Security checklist

- [ ] Hub UI port (4444) is loopback only OR placed behind a trusted reverse proxy
- [ ] If running tests against untrusted URLs, run this stack in an
      isolated network — Chromium is the security boundary, not Docker
- [ ] If you enabled VNC, the password is strong and the port is not on
      a public interface
- [ ] Resource limits sized to your host (browser nodes are memory-hungry)

## Troubleshooting

**`docker compose up` succeeds but `docker compose ps` shows the node
unhealthy**: the node 5555 healthcheck only reports healthy after it
has registered with the hub. Give it 30–60 seconds — `start_period`
is set accordingly.

**`Could not start a new session. Possible causes are invalid address
of the remote server or browser start-up failure`**: usually shm_size
too small or memory limit too tight. Don't lower `shm_size` below 2 GB.

**Tests hang / zombie sessions**: `SE_NODE_SESSION_TIMEOUT=300` kills
sessions idle for 5 minutes. Lower it if your tests should fail fast.

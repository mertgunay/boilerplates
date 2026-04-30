# Contributing

Pull requests welcome. The bar for what gets merged is high but not
mysterious — read this once and you'll know what to expect.

## What this repo accepts

- **New stacks** that match the conventions below and pull their
  weight (something more than a vendor quickstart with a healthcheck
  glued on). File a [new-stack issue](https://github.com/mertgunay/homelab/issues/new?template=new_stack.yml)
  first to check fit before you write a PR.
- **Fixes** to existing stacks: image bumps, healthcheck adjustments,
  README corrections, security tightening.
- **Documentation** improvements — both per-stack READMEs and the
  cross-cutting docs at the repo root.

## What this repo does not accept

- Stacks that depend on a shared base image, a shared network, or any
  other implicit cross-stack coupling. Each directory under `compose/`
  must boot in isolation.
- Anything that depends on a specific cloud provider, hosted service,
  or paid SaaS. The point of self-hosting is that the stack runs
  anywhere.
- Real secrets, production hostnames, or internal infrastructure
  references.
- Kubernetes manifests, Terraform / OpenTofu modules, Ansible roles.
  This repo is Compose-only — those belong elsewhere.

## Conventions every stack must follow

These show up in every existing stack and the per-stack READMEs
assume them. PRs that violate one without a written reason get
review feedback, not a merge.

- **Pinned image versions.** No `:latest`. The repo's promise is
  that `docker compose up -d` does the same thing a year from now.
- **Healthchecks** on every service that supports an in-container
  probe. If the image is distroless (no shell, no curl/wget),
  document that with a one-line comment and have dependents wait
  on `condition: service_started` instead.
- **Resource limits** on every service (`deploy.resources.limits`).
  A runaway process must not be able to take the host down.
- **Defensive port bindings.** Admin / debug UIs default to
  `127.0.0.1:<port>`. Only services that are inherently
  public-facing (NPM, signoz-with-nginx, teleport) bind on all
  interfaces.
- **Required env keys are blank** in `.env.example` and guarded by
  `${VAR:?<actionable message>}` (or `secrets.environment:`) in
  compose. Running `docker compose up` against a missing key must
  fail loudly — not silently ship a default password.
- **Internal networks** with `internal: true` for any service that
  should have no route off the bridge (e.g. NPM ↔ MariaDB).
- **Named volumes** (no `external: true`). Fresh deployments must
  not depend on pre-existing volumes.
- **`x-logging-default` anchor** for log rotation: 50 MB × 5 files,
  gzip. Reuse via `logging: *logging-default`.
- **Per-stack README** with: quick start, customisation knobs,
  backup story, security checklist, common troubleshooting.
- **English** in comments, docs, commit messages, and PR
  descriptions.

## Workflow

1. Open an issue first if your change is non-trivial.
2. Fork → branch → PR. One logical change per PR.
3. Imperative commit messages (`fix(redis): ...`, `feat(nginx): ...`).
   Conventional Commit prefixes are appreciated but not required.
4. Run `docker compose config -q` for the affected stack(s) before
   pushing.
5. The validate workflow on your PR runs the same `compose config`
   check + yamllint + hadolint + shellcheck. Fix anything red.
6. PR description: what changed, why, how you tested. The PR
   template covers the rest.

## Style

- Comments explain *why*, not *what*. The compose file already says
  what it does.
- Keep lines under ~100 chars in compose / config files. READMEs
  can wrap softly at ~80.
- Follow the file layout of the existing stacks: `compose.yml`,
  `.env.example`, `README.md`, plus optional `config/` and
  `Dockerfile` where needed.

## License

By submitting a PR you agree to license your contribution under
[MIT](LICENSE), the repo's license.

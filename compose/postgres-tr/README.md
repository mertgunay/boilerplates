# postgres-tr

**Self-hosted PostgreSQL with Turkish locale (`tr_TR.UTF-8`)** baked
into a custom image. Same shape as
[`compose/postgres`](../postgres/README.md) (secrets, healthcheck,
network defaults, log rotation) — see that README for the bulk of
the documentation.

> Boilerplate / starter. Same disclaimers as the generic stack apply.

## When to use this

Pick this variant if you need Turkish collation or case-folding at the
database level — for example `ORDER BY name COLLATE "tr_TR.utf8"` to sort
"İstanbul" correctly, or you want the cluster's default `LC_COLLATE` /
`LC_CTYPE` to be `tr_TR.UTF-8` so unqualified text comparisons follow
Turkish rules.

If you do not need any of the above, prefer the generic
[`compose/postgres`](../postgres) stack — smaller image, no custom build.

## Why a custom Dockerfile

PostgreSQL locks the cluster locale at `initdb` time. The locale must exist
on the OS **before** the cluster is created on first boot. The Alpine-based
official image is awkward for this (musl + non-default locales), so this
variant uses the Debian-based `postgres:17` and runs `localedef` during the
image build.

## Quick start

```sh
cp .env.example .env          # edit and set real values
docker compose up -d --build  # --build the first time so the image gets created
docker compose ps
```

## Locale is set at first boot only

`POSTGRES_INITDB_ARGS` and `LANG` take effect **only** when the data
directory is empty. To change the cluster locale after the fact you must:

1. `pg_dumpall` the current cluster
2. Stop the stack and remove the `pg_data` volume
3. Update locale settings, `docker compose up -d --build`
4. Restore from the dump

## What is different from the generic stack

| Aspect                   | Generic               | This (tr)                    |
| ------------------------ | --------------------- | ---------------------------- |
| Image source             | Pulled (`postgres:17-alpine`) | Built locally (`postgres:17` + `localedef`) |
| Container name           | `postgres`            | `postgres-tr`                |
| `LANG`                   | image default         | `tr_TR.UTF-8`                |
| `POSTGRES_INITDB_ARGS`   | unset                 | `--locale=tr_TR.UTF-8 --encoding=UTF8` |
| First boot               | `up -d`               | `up -d --build`              |

Everything else (secrets layout, ports, healthcheck, log rotation, resource
limits, networking alternatives, backups) follows the generic stack.

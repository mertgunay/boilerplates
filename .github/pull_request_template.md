<!--
Thanks for contributing! Briefly:
  - Open one PR per logical change.
  - Imperative commit messages ("add otel agent", not "added otel agent").
  - Comments and docs in English.
-->

## What

<!-- One paragraph: what does this PR change and why? -->

## How tested

<!--
At minimum: `docker compose config -q` passes for the affected stack.
Ideally: `docker compose up -d`, services reach `healthy`, smoke
test (curl, psql, redis-cli, etc.). Mention what you ran.
-->

## Checklist

- [ ] All images pinned to a specific tag (no `:latest`)
- [ ] Healthchecks present where the image supports them, or a one-line comment explains why not (e.g. distroless)
- [ ] Resource limits set (`deploy.resources.limits`)
- [ ] Defensive port bindings — admin / debug UIs default to `127.0.0.1`
- [ ] Required env keys are blank in `.env.example`, guarded by `${VAR:?}` (or `secrets.environment:`) in compose
- [ ] No real secrets, hostnames, or internal infrastructure references in the diff
- [ ] If a new stack: per-stack README with quick start, customisation, backup, security checklist, troubleshooting
- [ ] Top-level README "Stacks" table updated if a stack is added or removed
- [ ] `docker compose config -q` runs clean for every affected stack

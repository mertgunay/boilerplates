# Security policy

## Reporting a vulnerability

If you find a security issue in any of the boilerplates here — a
default config that exposes a port it shouldn't, a privilege the
container does not need, a secret that leaks somewhere, an outdated
image with a known CVE — please report it privately first. **Do not
open a public issue.**

Two ways to reach out, in order of preference:

1. **GitHub Security Advisories.** Use the
   [Report a vulnerability](https://github.com/mertgunay/boilerplates/security/advisories/new)
   button on this repo's Security tab. This keeps the discussion
   private until a fix is ready.
2. **Email.** `se.mertgunay@gmail.com`. Mention "boilerplates security"
   in the subject so it doesn't get filtered.

Please include:

- Which stack the issue is in (`compose/<name>`).
- A short reproduction (config diff, attack scenario, or CVE link).
- Whether you're OK with public credit after the fix lands.

## What this project is

These are **starter Docker Compose stacks**. They have hardened
defaults but are not a hardening guarantee:

- The defaults assume you are running the stack in a private network
  and put your own auth / TLS layer in front of it where appropriate.
- Image versions are pinned, but pinning is only as fresh as the last
  Dependabot PR. If you fork the repo, keep up with those PRs.
- Each stack's README has a "Security checklist" section. Treat that
  list as the minimum bar before pointing real traffic at it.

## Scope

In scope for a security report:

- Default configurations that meaningfully widen the attack surface
  beyond what the upstream image already exposes.
- Secrets / credentials accidentally committed to the repo.
- Pinned image versions with known unpatched CVEs.
- Dockerfile build patterns that leak secrets into image layers.
- Compose mounts that grant unnecessary host access.

Out of scope:

- General hardening suggestions for the upstream images themselves —
  those belong upstream.
- Issues that only manifest when you deviate from the documented
  defaults (e.g. you removed the `:?` guard, then ran with empty
  secrets).
- Theoretical attacks against your own already-compromised host.

## Disclosure

Once a fix is available, the security advisory becomes public with a
CVE if appropriate. Reporters get credit unless they ask otherwise.

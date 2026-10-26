# Staging

Production with `bulbashenko.com` replaced by `bulbashenko.dev`, reachable only over the mesh. Its own domain keeps
the production Ory session cookie (domain `bulbashenko.com`) away from staging code. Design and order of work:
infra#121.

| Production | Staging |
|---|---|
| `bulbashenko.com` | `bulbashenko.dev` |
| `auth.bulbashenko.com` | `auth.bulbashenko.dev` |
| `users.int.bulbashenko.com` | `users.int.bulbashenko.dev` |
| `media.bulbashenko.com` | `media.bulbashenko.dev` |
| Kratos mail via Stalwart | `mailpit.int.bulbashenko.dev` (nothing leaves the cluster) |

- Namespaces `site-staging` and `auth-staging` (one per app, as in production), labelled `bulbashenko.com/env: staging`.
- Data: roles and databases `*_staging` in the production CNPG cluster `pg`, bucket `media-staging` with its own key
  (both in `apps/production/data`). Not in the backups.
- Names resolve through Headscale (extra records plus a split route for `bulbashenko.dev`); TLS from the
  `staging-wildcard` certificate (`tls/`) in Traefik's default TLSStore.

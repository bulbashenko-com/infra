# Staging

Production with `bulbashenko.com` replaced by `bulbashenko.dev`, reachable only over the mesh. Its own domain keeps
the production Ory session cookie (domain `bulbashenko.com`) away from staging code. Design: infra#121.

| Production | Staging |
|---|---|
| `bulbashenko.com` | `bulbashenko.dev` |
| `auth.bulbashenko.com` | `auth.bulbashenko.dev` (next: #81) |
| `users.int.bulbashenko.com` | `users.int.bulbashenko.dev` (next: #81) |
| `media.bulbashenko.com` | `media.bulbashenko.dev` |

- **Branches.** This directory is read from `dev` by the Flux Kustomization `staging`, which runs as
  `staging-reconciler`: full rights in `site-staging` and `auth-staging`, none elsewhere. What staging needs outside
  them (namespaces, RBAC, the `staging-wildcard` certificate, the content export) is in `apps/staging-platform`,
  from `main`, so it changes with a release.
- **Same build.** The site runs the image pinned in `apps/base/site` for both environments; staging gets a new pin at
  once, production with the release. Environment differences: `site-env` ConfigMap, Secret, route.
- **Data.** Database `bulbashenko_staging` and bucket `media-staging` (in `apps/production/data`, not backed up).
  Production exports its content nightly (02:30 UTC, `staging-seed-export` in `data`; admin sessions left out) into
  the bucket `staging-seed`. `just staging-refresh` re-runs the Job `staging-refresh`, which restores that dump and
  mirrors `media` into `media-staging`. Staging never holds credentials for production's database.
- Names resolve through Headscale (extra records plus a split route for `bulbashenko.dev`).

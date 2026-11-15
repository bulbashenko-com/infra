# Staging

Production with `bulbashenko.com` replaced by `bulbashenko.dev`, reachable only over the mesh. Its own domain keeps
the production Ory session cookie (domain `bulbashenko.com`) away from staging code. Design: infra#121.

| Production | Staging |
|---|---|
| `bulbashenko.com` | `bulbashenko.dev` |
| `auth.bulbashenko.com` | `auth.bulbashenko.dev` |
| `users.int.bulbashenko.com` | `users.int.bulbashenko.dev` |
| Kratos mail via Stalwart | `mailpit.int.bulbashenko.dev` (nothing leaves the cluster) |

- **Branches.** This directory is read from `dev` by the Flux Kustomization `staging`, which runs as
  `staging-reconciler`: full rights in `site-staging` and `auth-staging`, none elsewhere. What staging needs outside
  them (namespaces, RBAC, the `staging-wildcard` certificate, the content export) is in `apps/staging-platform`,
  from `main`, so it changes with a release.
- **Same build.** The site runs the image pinned in `apps/base/site` for both environments; staging gets a new pin at
  once, production with the release. Environment differences: `site-env` ConfigMap, Secret, route.
- **Data.** Database `bulbashenko_staging` (in `apps/production/data`, not backed up). Production exports its
  content nightly (02:30 UTC, `staging-seed-export` in `data`; admin sessions left out) into the bucket
  `staging-seed`. Staging restores that dump nightly at 03:15 UTC (CronJob `staging-refresh`; an extra run:
  `just staging-refresh`). Staging never holds credentials for production's database. No Nextcloud: the gallery and
  files stay empty.
- **Ory** (`auth/`): bulbashenko-com/auth's root base plus its staging component (`deploy/staging`), at the same
  commit as production (`promote.sh` moves both pins). Own databases and keys, OIDC clients for the staging site and
  the e2e apps, mailpit, and an `admin` account seeded once (the Job `seed-admin` logs its recovery link).
- **Release gate.** Each auth version runs the e2e suite in staging (Job `e2e` in its own Kustomization `auth-e2e`,
  manifests in `auth/e2e/`, read from dev, started after the stack's is ready on the same commit). Flux posts the
  result as the commit status `staging/auth-e2e` on the dev commit it tested (`apps/staging-platform/notify.yaml`,
  deploy App); merging the release PR into main requires it. Hotfix PRs get it from `.github/workflows/staging-gate.yml`.
- Names resolve through Headscale (extra records plus a split route for `bulbashenko.dev`).

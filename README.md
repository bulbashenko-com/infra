# infra

Single source of truth for the bulbashenko.com platform. If it runs, it is described here.

| Layer | Tool | Path |
|---|---|---|
| Servers, firewalls, network, IPs, DNS, Tunnel | OpenTofu (hcloud, cloudflare) | `terraform/` |
| Cluster bootstrap and reconciliation | Flux (branch `production`; staging from `main`) | `clusters/hel1/` |
| Platform (ingress, certs, tunnel, DB operator, monitoring, backups) | Flux + Helm | `infrastructure/` |
| Applications | Flux + Kustomize | `apps/{base,staging,production}/` |
| Secrets | SOPS + age | `*.sops.yaml` next to what uses them |

## Rules

- Two branches. `main` is **staging**: every change lands there through a pull request (CI green; agents may
  auto-merge). `production` is what runs: Flux syncs `clusters/hel1` from it. A release is one pull request
  `main -> production`, kept open and described by a bot; the owner merges it. See [Releases](#releases).
- Secrets are committed **only** encrypted, in `*.sops.yaml`. CI rejects plaintext `kind: Secret` and unencrypted `*.sops.*` files; gitleaks scans every push.
- App versions: a push to `main` in an app repo (site, auth, mail, teamspeak) pins the new commit on `main` here
  (image tag or Flux `GitRepository` commit), straight away and without a PR; production gets it with the release.
  By hand: `just promote <app> [sha]` (an older sha rolls back; preview: `just promote-dry`).
- Rollback = `git revert` (in `production`, or revert the release merge).

## Recovery from zero

1. This repo.
2. The age private key (offline copy with the owner).
3. Data backups on the Hetzner Storage Box (rclone crypt, `box:hel1`): CNPG base backups + WAL (60 days),
   Garage buckets, Headscale/TeamSpeak volume archives. Rehearsed with `apps/production/drill`.

`tofu apply` → servers come up with k3s via cloud-init → `flux bootstrap` → Flux restores everything else → restore data.

## Layout

```
terraform/           OpenTofu, state committed encrypted
clusters/hel1/       Flux entry point for the hel1 cluster
infrastructure/      cluster-wide components
apps/base/           app manifests
apps/staging/        staging overlays (*.int, own Ory, *_staging DBs)
apps/production/     production overlays (pinned image digests)
scripts/             helpers used by CI and the justfile
```

Daily commands: `just --list`.

## Labels

Every namespace and every object we manage carries two labels (staging a third), so "mine" and "the machinery" are easy to tell apart (Headlamp, k9s, `kubectl get -l`).

| Label | Values |
|---|---|
| `bulbashenko.com/layer` | `app`: our services (site, auth, data). `platform`: what we install for them (tunnel, certs, Postgres operator, ingress, GitOps UI, access). `system`: Kubernetes/k3s internals, not touched. |
| `bulbashenko.com/app` | `site`, `auth`, `data`, `tunnel`, `certs`, `postgres-operator`, `ingress`, `gitops`, `access`, `monitoring`, `controllers`, `configs`, `kubernetes` |
| `bulbashenko.com/env` | `staging` on everything in `apps/staging` (namespaces `*-staging`); production objects have no `env` label. |

Where they come from: Namespace manifests (explicit), `labels:` in each directory's `kustomization.yaml` (`includeSelectors: false`; pod templates included for apps), Flux `commonMetadata` for the auth repo, and `infrastructure/configs/system-namespaces.yaml` for namespaces Kubernetes or Flux create themselves (prune disabled).

Examples: `kubectl get pods -A -l bulbashenko.com/layer=app`, in k9s `:pods` then `/-l bulbashenko.com/layer=app`.
kube-state-metrics exports both labels (`label_bulbashenko_com_layer`, `label_bulbashenko_com_app` on `kube_namespace_labels`
and `kube_pod_labels`); the Grafana home dashboard "Главное" groups CPU and memory by them.

## Monitoring

victoria-metrics-k8s-stack in `monitoring`: the operator (`infrastructure/controllers/victoria-metrics-operator.yaml`, brings
the CRDs) and the stack (`infrastructure/configs/monitoring/`: VMSingle with 30 days retention, vmagent, vmalert,
Alertmanager, node-exporter, kube-state-metrics, Grafana).

- Grafana: https://grafana.int.bulbashenko.com (mesh only, sign-in through Ory client `grafana`; only `infra-admins` get in,
  as Grafana server admins). No PVC: dashboards and datasources come from git, upstream dashboards and alert rules from the
  chart's sync Job. Break-glass: `/login?disableAutoLogin` with the local admin from the Secret `grafana`.
- "Главное" (`infrastructure/configs/monitoring/dashboards/main.json`, Grafana's home page): everything on one page:
  status, backups and data, nodes, layers and apps, traffic, mail, GitOps, scrape targets. Upstream dashboards (Node
  Exporter Full, Kubernetes views, VictoriaMetrics) stay for drilling down. The JSON is generated: edit
  `scripts/dashboard-main.py` and run it (usage in the file), don't hand-edit the JSON.
- Deploys on the same page: Flux versions and status, rollout progress, typical deploy duration, open PRs and
  GitHub Actions runs (GitHub datasource through the read-only GitHub App `bulbashenko-com-grafana`, credentials in the
  Secret `grafana`: `github-app-id`, `github-app-installation-id`, `github-app-private-key`). Every graph carries
  deploy markers built from metrics, so they survive Grafana restarts.
- Scrape targets: platform components in `infrastructure/configs/monitoring/scrapes.yaml`; app targets next to the app
  (`apps/production/data/scrapes.yaml` for CNPG and Garage, `apps/mail/scrape.yaml` for Stalwart).
- Alerts: upstream rules (synced by the chart) plus ours in `infrastructure/configs/monitoring/rules.yaml` (backups,
  WAL, replication, Garage, tunnel, certificates, 5xx, OOM kills, Flux). Alertmanager has no receiver yet (Telegram: infra#75).

## Releases

```
app repo: push to main ─► CI / image ─► request-promote.yml ──dispatch──► infra: promote.yml ─► commit on main (pin)
you / agent: PR ─► CI ─► merge into main ───────────────────────────────────────────────────────┘
main ─► staging (apps/staging, read from main)            release.yml keeps PR "Release" main -> production open
owner merges the release PR ─► production ─► Flux ─► the cluster (everything in clusters/hel1)
```

| App | Gate before the pin | Pin |
|---|---|---|
| site | image `ghcr.io/bulbashenko-com/site:<sha>` pushed | `apps/production/site/kustomization.yaml` `newTag` |
| auth | `test` (UI + e2e) green, then image `auth-ui:<sha>` pushed | `clusters/hel1/auth.yaml` `commit` + `newTag` |
| mail | `CI` green | `clusters/hel1/mail.yaml` `commit` |
| teamspeak | `CI` green | `clusters/hel1/teamspeak.yaml` `commit` |

- `scripts/promote.sh` commits the pin to `main` as the deploy App (fast-forward, retried if `main` moves). A request
  older than the current pin is skipped, so out-of-order dispatches never roll back; a manual run may (rollback).
  The commit message lists the app's commits since the previous pin.
- `scripts/release-pr.sh` (workflow `release`, on every push to `main` or `production`) keeps one PR
  `main -> production`: apps, other changes, and a warning for cluster-wide paths (`infrastructure/`, `apps/edge/`,
  cluster-level Flux objects), which have no staging copy and first apply with the release. Merge it with a merge
  commit only; that is how the next release knows what is already out.
- Hotfix: PR straight into `production`; the workflow opens an auto-merging back-merge PR into `main`.
- `terraform/` is not deployed by Flux: after a release that touches it, the owner runs `just plan` / `just apply`.
- Credentials: GitHub App `bulbashenko-com-deploy` (Contents + Pull requests: write), installed on `infra` only, and
  allowed to bypass the `main` ruleset (it pushes the pins). Org variable `DEPLOY_APP_CLIENT_ID`, org secret
  `DEPLOY_APP_PRIVATE_KEY`. An App token (not `GITHUB_TOKEN`) is required so its PRs run the required checks.
- Add an app: a `case` line in `scripts/promote.sh`, the choice in `promote.yml`, and a `request-promote.yml` job in its repo.

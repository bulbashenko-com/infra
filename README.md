# infra

Single source of truth for the bulbashenko.com platform. If it runs, it is described here.

| Layer | Tool | Path |
|---|---|---|
| Servers, firewalls, network, IPs, DNS, Tunnel | OpenTofu (hcloud, cloudflare) | `terraform/` |
| Cluster bootstrap and reconciliation | Flux | `clusters/hel1/` |
| Platform (ingress, certs, tunnel, DB operator, monitoring, backups) | Flux + Helm | `infrastructure/` |
| Applications | Flux + Kustomize | `apps/{base,staging,production}/` |
| Secrets | SOPS + age | `*.sops.yaml` next to what uses them |

## Rules

- Change = pull request. `main` is protected; CI must be green.
- Secrets are committed **only** encrypted, in `*.sops.yaml`. CI rejects plaintext `kind: Secret` and unencrypted `*.sops.*` files; gitleaks scans every push.
- Production deploys are pull requests. A push to `main` in an app repo (site, auth, mail, teamspeak) opens or refreshes
  the PR `deploy/<app>` here, pinning the new commit (image tag or Flux `GitRepository` commit); merge = deploy,
  close = skip. One rolling PR per app, never auto-merged. By hand: `just promote <app> [sha]` (preview: `just promote-dry`).
  Details: [Deploy PRs](#deploy-prs).
- Rollback = `git revert`.

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

Every namespace and every object we manage carries two labels, so "mine" and "the machinery" are easy to tell apart (Headlamp, k9s, `kubectl get -l`).

| Label | Values |
|---|---|
| `bulbashenko.com/layer` | `app`: our services (site, auth, data). `platform`: what we install for them (tunnel, certs, Postgres operator, ingress, GitOps UI, access). `system`: Kubernetes/k3s internals, not touched. |
| `bulbashenko.com/app` | `site`, `auth`, `data`, `tunnel`, `certs`, `postgres-operator`, `ingress`, `gitops`, `access`, `monitoring`, `controllers`, `configs`, `kubernetes` |

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
  Exporter Full, Kubernetes views, VictoriaMetrics) stay for drilling down.
- Scrape targets: platform components in `infrastructure/configs/monitoring/scrapes.yaml`; app targets next to the app
  (`apps/production/data/scrapes.yaml` for CNPG and Garage, `apps/mail/scrape.yaml` for Stalwart).
- Alerts: upstream rules (synced by the chart) plus ours in `infrastructure/configs/monitoring/rules.yaml` (backups,
  WAL, replication, Garage, tunnel, certificates, 5xx, OOM kills, Flux). Alertmanager has no receiver yet (Telegram: infra#75).

## Deploy PRs

```
app repo: push to main ─► CI / image build ─► request-promote.yml ──repository_dispatch──► infra: promote.yml
                                                                                              │ scripts/promote.sh
                                                                         PR deploy/<app> ◄────┘ (owner merges or closes)
```

| App | Gate before the PR | Pin changed |
|---|---|---|
| site | image `ghcr.io/bulbashenko-com/site:<sha>` pushed | `apps/production/site/kustomization.yaml` `newTag` |
| auth | `test` (UI + e2e) green, then image `auth-ui:<sha>` pushed | `clusters/hel1/auth.yaml` `commit` + `newTag` |
| mail | `CI` green | `clusters/hel1/mail.yaml` `commit` |
| teamspeak | `CI` green | `clusters/hel1/teamspeak.yaml` `commit` |

- The PR body lists the commits between what production runs and the new pin, and warns on rollbacks.
- A newer push force-updates the same `deploy/<app>` branch; an older request never overwrites a newer pending one.
- Closing the PR keeps production as is; the next push to that app opens a new one.
- Credentials: GitHub App `bulbashenko-com-deploy` (Contents + Pull requests: write), installed on `infra` only.
  Org variable `DEPLOY_APP_CLIENT_ID` and org secret `DEPLOY_APP_PRIVATE_KEY`, visible to infra and the app repos.
  An App token (not `GITHUB_TOKEN`) is required so the PR runs the required checks.
- Add an app: a `case` line in `scripts/promote.sh`, the choice in `promote.yml`, and a `request-promote.yml` job in its repo.

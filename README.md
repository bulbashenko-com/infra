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
- Staging deploys automatically. Production changes only by an image digest promoted from staging (`just promote <app>`).
- Rollback = `git revert`.

## Recovery from zero

1. This repo.
2. The age private key (offline copy with the owner).
3. Data backups on the Hetzner Storage Box (restic, CNPG WAL).

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

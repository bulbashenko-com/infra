# Working on infra (instructions for AI agents)

- Branches: `main` is **production** (Flux syncs `clusters/hel1` from it), `dev` is **staging** and the default branch (`apps/staging` is read from it). Every change goes through a branch + PR into `dev`. Never push to `dev` or `main` directly (only the deploy App pushes pins to `dev`).
- Merge policy (owner decision, 2026-10-26, replaces the 2026-10-11 one): agents may merge or auto-merge their PRs into `dev` once the required checks pass; that is staging. Production changes only through the release PR `dev -> main` (`scripts/release-pr.sh` keeps it open), which **the owner merges** (merge commit only). Agents never merge into `main`. Hotfix: PR into `main` (owner merges), the back-merge to `dev` is automatic. `tofu apply` stays with the owner.
- Recreating a server: Hetzner no longer sells CX22 (use CX23); drop the server's import block in `terraform/imports.tf`; primary IPs are protected, separate resources (no assignee fields in config).
- Cluster access is read-only: always `KUBECONFIG=~/.kube/hel1-readonly.yaml` (ServiceAccount `access/claude-readonly`, role `view`, no Secrets). `~/.kube/hel1-admin.yaml` is the owner's break-glass: never use it, even though it is readable on this machine. Never run `kubectl apply/edit/delete` or `helm install` against the cluster: Flux owns the state.
- App versions are pinned by `scripts/promote.sh` (`.github/workflows/promote.yml`): the deploy App commits the pin to `dev`, production gets it with the release. Use `just promote <app> [sha]` instead of editing pins by hand.
- Changes under `infrastructure/`, `apps/edge/` and cluster-level Flux objects have no staging copy: they first apply with the release. Say so in the PR.
- `tofu apply` is run by the owner. You may run `tofu plan` and paste a summary.
- Secrets: edit with `sops <file>`; never print decrypted values, never write decrypted files into the repo, never put secret values in commit messages, PR bodies or chat.
- Prefer `just` recipes over long ad-hoc commands; they print compact output. Add a recipe instead of repeating a long command.
- Before changing a third-party component, read its current docs for the pinned version.
- Every new namespace and kustomization directory gets the ownership labels `bulbashenko.com/layer` and `bulbashenko.com/app` (README: Labels).
- Commit style: short imperative subject, explain why in the body.

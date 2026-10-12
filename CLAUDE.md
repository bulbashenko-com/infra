# Working on infra (instructions for AI agents)

- Every change goes through a branch + PR. Never push to `main`.
- Merge policy (owner decision, 2026-10-11; migration finished 2026-10-12): agents open PRs but do **not** merge or enable auto-merge for production (`apps/production/`, `apps/edge/`, `apps/mail/`, `clusters/`, `terraform/`, `infrastructure/`); the owner merges. Auto-merge is allowed only for staging and for the state PRs that `just apply` opens. `tofu apply` stays with the owner.
- Recreating a server: Hetzner no longer sells CX22 (use CX23); drop the server's import block in `terraform/imports.tf`; primary IPs are protected, separate resources (no assignee fields in config).
- Cluster access is read-only: always `KUBECONFIG=~/.kube/hel1-readonly.yaml` (ServiceAccount `access/claude-readonly`, role `view`, no Secrets). `~/.kube/hel1-admin.yaml` is the owner's break-glass: never use it, even though it is readable on this machine. Never run `kubectl apply/edit/delete` or `helm install` against the cluster: Flux owns the state.
- App versions in production change only through deploy PRs (`deploy/<app>`, opened by `.github/workflows/promote.yml`); to request one use `just promote <app> [sha]` instead of editing pins by hand. Never merge them.
- `tofu apply` is run by the owner. You may run `tofu plan` and paste a summary.
- Secrets: edit with `sops <file>`; never print decrypted values, never write decrypted files into the repo, never put secret values in commit messages, PR bodies or chat.
- Prefer `just` recipes over long ad-hoc commands; they print compact output. Add a recipe instead of repeating a long command.
- Before changing a third-party component, read its current docs for the pinned version.
- Every new namespace and kustomization directory gets the ownership labels `bulbashenko.com/layer` and `bulbashenko.com/app` (README: Labels).
- Commit style: short imperative subject, explain why in the body.

# Working on infra (instructions for AI agents)

- Every change goes through a branch + PR. Never push to `main`.
- Merge policy (owner decision, 2026-10-11):
  - **During the migration off Coolify** (until Coolify is removed): agents may enable GitHub auto-merge on their own PRs, production included; they merge once CI is green. `tofu apply` stays with the owner.
  - **After the migration**: auto-merge only for staging; production PRs (`apps/production/`, `clusters/`, `terraform/`, `infrastructure/`) are merged by the owner by hand.
- Cluster access is read-only: always `KUBECONFIG=~/.kube/hel1-readonly.yaml` (ServiceAccount `access/claude-readonly`, role `view`, no Secrets). `~/.kube/hel1-admin.yaml` is the owner's break-glass: never use it, even though it is readable on this machine. Never run `kubectl apply/edit/delete` or `helm install` against the cluster: Flux owns the state.
- `tofu apply` is run by the owner. You may run `tofu plan` and paste a summary.
- Secrets: edit with `sops <file>`; never print decrypted values, never write decrypted files into the repo, never put secret values in commit messages, PR bodies or chat.
- Prefer `just` recipes over long ad-hoc commands; they print compact output. Add a recipe instead of repeating a long command.
- Before changing a third-party component, read its current docs for the pinned version.
- Commit style: short imperative subject, explain why in the body.

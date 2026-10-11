# Working on infra (instructions for AI agents)

- Every change goes through a branch + PR. Never push to `main`, never merge a PR that touches `apps/production/`, `clusters/` or `terraform/`: the owner merges those. Staging-only PRs may be merged once CI is green.
- Cluster access is read-only (ServiceAccount with `view`, no Secrets). Do not ask for or use admin kubeconfigs. Never run `kubectl apply/edit/delete` or `helm install` against the cluster: Flux owns the state.
- `tofu apply` is run by the owner. You may run `tofu plan` and paste a summary.
- Secrets: edit with `sops <file>`; never print decrypted values, never write decrypted files into the repo, never put secret values in commit messages, PR bodies or chat.
- Prefer `just` recipes over long ad-hoc commands; they print compact output. Add a recipe instead of repeating a long command.
- Before changing a third-party component, read its current docs for the pinned version.
- Commit style: short imperative subject, explain why in the body.

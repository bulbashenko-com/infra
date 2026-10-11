set shell := ["bash", "-euo", "pipefail", "-c"]

# list recipes
default:
    @just --list

# run all local checks (gitleaks, SOPS, fmt)
check:
    pre-commit run --all-files

# edit an encrypted file (creates it if missing)
secret file:
    sops {{file}}

tofu := "sops exec-env secrets.sops.env"

# OpenTofu plan (credentials from terraform/secrets.sops.env)
plan:
    cd terraform && {{tofu}} 'tofu init -input=false >/dev/null && tofu plan -input=false -compact-warnings'

# OpenTofu apply: owner only. Then ships the new encrypted state as an auto-merging PR.
apply:
    cd terraform && {{tofu}} 'tofu apply -input=false'
    just _ship-state

# commit terraform.tfstate on a state/* branch and open an auto-merge PR
_ship-state:
    #!/usr/bin/env bash
    set -euo pipefail
    f=terraform/terraform.tfstate
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1 && git diff --quiet -- "$f"; then
      echo "state unchanged"; exit 0
    fi
    grep -q '"encrypted_data"' "$f" || { echo "refusing: $f is not encrypted" >&2; exit 1; }
    b="state/$(date -u +%Y%m%d-%H%M%S)"
    git switch -q -c "$b"
    git add "$f"
    git commit -q -m "Update encrypted state after apply"
    git push -q -u origin "$b"
    gh pr create --base main --title "State after apply ($b)" --body "Encrypted terraform.tfstate written by \`just apply\`."
    gh pr merge --auto --merge --delete-branch
    echo "Staying on $b. After the PR merges: git switch main && git pull"


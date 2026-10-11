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
    git -c credential.helper= -c credential.helper='!gh auth git-credential' push -q -u origin "$b"
    gh pr create --base main --title "State after apply ($b)" --body "Encrypted terraform.tfstate written by \`just apply\`."
    gh pr merge --auto --merge --delete-branch
    echo "Staying on $b. After the PR merges: git switch main && git pull"


# one-time Headscale pre-auth key (tag:core, 30 min) into terraform/secrets.sops.env; asks for your sudo password on hel1-edge
node-key:
    #!/usr/bin/env bash
    set -euo pipefail
    read -rsp "sudo password on hel1-edge: " pw; echo
    out=$(printf '%s\n' "$pw" | ssh bulbashenko@62.238.18.202 \
      'sudo -S -p "" docker exec headscale-gml9nuytnpijytqxqkundgva headscale preauthkeys create --tags tag:core --expiration 30m -o json')
    unset pw
    key=$(printf '%s' "$out" | jq -r '.key // empty' 2>/dev/null || true)
    if [ -z "$key" ]; then
      echo "no key in headscale output; its shape (values hidden):" >&2
      printf '%s' "$out" | jq -c 'paths(scalars) | map(tostring) | join(".")' 2>/dev/null >&2 || printf '%s\n' "$out" | sed 's/[A-Za-z0-9]\{20,\}/<redacted>/g' >&2
      exit 1
    fi
    printf '%s' "$key" | jq -Rs . | sops set --value-stdin terraform/secrets.sops.env '["TF_VAR_tailscale_authkey"]'
    echo "pre-auth key stored (expires in 30 min): run just apply now"

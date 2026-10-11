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

# OpenTofu plan (needs TF_VAR_state_passphrase and provider tokens, see terraform/README.md)
plan:
    cd terraform && tofu init -input=false >/dev/null && tofu plan -input=false

# OpenTofu apply: owner only
apply:
    cd terraform && tofu apply -input=false

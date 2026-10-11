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

# OpenTofu apply: owner only
apply:
    cd terraform && {{tofu}} 'tofu apply -input=false'

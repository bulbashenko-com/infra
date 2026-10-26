#!/usr/bin/env bash
# One-time setup for OpenTofu in CI (.github/workflows/tofu.yml): plan on pull requests with read-only credentials,
# apply on main with read-write ones, state in Cloudflare R2. Run by the owner from the repo root: it creates API
# tokens and GitHub secrets, which agents may not do. Prints no secret; leaves the changed files for a commit.
#
#   just tofu-ci-bootstrap
#
# Creates:
#   Cloudflare account tokens  tofu-apply (DNS, zone settings, tunnel), tofu-plan (the same, read-only),
#                              tofu-state-rw / tofu-state-ro (only the R2 bucket bulbashenko-tofu-state)
#   age keys                   tofu-plan, tofu-apply: GitHub secrets SOPS_AGE_KEY_PLAN (repo) and
#                              SOPS_AGE_KEY_APPLY (environment `production`, branch main only)
#   files                      terraform/creds-plan.sops.env, terraform/creds-apply.sops.env, terraform/owner.sops.env;
#                              terraform/secrets.sops.env keeps only the TF_VARs; .sops.yaml gets the CI recipients
# Asks for one value: a read-only Hetzner Cloud token (Hetzner has no API to create tokens).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
export PATH="$HOME/.local/bin:$PATH"  # cf

acct=e6a72845a55a3840d8b52c2d7fdf3004
repo=bulbashenko-com/infra
bucket=bulbashenko-tofu-state
zone_com=abb0bea137c9c120a465f8a609c98e02
zone_dev=0a900192bbd9a29f95f3ccb7e01a6332
owner_key=age12qgx04vs6thq39ym6jl5wlgcymjzrdln7w6wyck7px28k4p8fedq09dq5g

[ ! -e terraform/creds-apply.sops.env ] || { echo "already bootstrapped (terraform/creds-apply.sops.env exists)" >&2; exit 1; }
for t in cf sops age-keygen jq gh sha256sum; do command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; done

umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

read -rsp "Hetzner Cloud API token, Read only (Console -> project -> Security -> API tokens): " hcloud_ro; echo
[ ${#hcloud_ro} -ge 32 ] || { echo "that does not look like a Hetzner token" >&2; exit 1; }

# Cloudflare permission groups (cf accounts tokens permission-groups list).
zone_read=c8fed203ed3043cba015a93ad1616f1f dns_read=82e64a83756745bbbb1c9c2701bf816b dns_write=4755a26eedb94da69e1066d98aa820be
zs_read=517b21aee92c4d89936c976ba6e4be55 zs_write=3030687196b94b638145a3953da2b699
tunnel_read=efea2ab8357b47888938f101ae5e053f tunnel_write=c07321b023e944ff818fec44d8203567
acct_settings_read=c1fde68c7bcc44588cbb6ddbc16d6480
r2_item_read=6a018a9f2fc74eb6b293b0c548f38b39 r2_item_write=2efd5506f9c8494dacb1fa10a3e7d5b6

zones="{\"com.cloudflare.api.account.zone.$zone_com\":\"*\",\"com.cloudflare.api.account.zone.$zone_dev\":\"*\"}"
account="{\"com.cloudflare.api.account.$acct\":\"*\"}"
state="{\"com.cloudflare.edge.r2.bucket.${acct}_default_${bucket}\":\"*\"}"
groups() { local out=; for g in "$@"; do out+="${out:+,}{\"id\":\"$g\"}"; done; printf '[%s]' "$out"; }
policy() { printf '{"effect":"allow","permission_groups":%s,"resources":%s}' "$1" "$2"; }

# token <name> <policies json> -> "<id> <value>" into $work/<name>
token() {
  env CLOUDFLARE_ACCOUNT_ID=$acct cf accounts tokens create --name "$1" --policies "$2" |
    jq -er '"\(.id) \(.value)"' > "$work/$1"
  echo "Cloudflare token $1 created"
}
token tofu-apply "[$(policy "$(groups $zone_read $dns_write $zs_write)" "$zones"),$(policy "$(groups $tunnel_write $acct_settings_read)" "$account")]"
token tofu-plan "[$(policy "$(groups $zone_read $dns_read $zs_read)" "$zones"),$(policy "$(groups $tunnel_read $acct_settings_read)" "$account")]"
token tofu-state-rw "[$(policy "$(groups $r2_item_read $r2_item_write)" "$state")]"
token tofu-state-ro "[$(policy "$(groups $r2_item_read)" "$state")]"
val() { cut -d' ' -f2 "$work/$1"; }
# R2's S3 credentials derive from an API token: access key = token id, secret = SHA-256 of the token value.
s3_id() { cut -d' ' -f1 "$work/$1"; }
s3_secret() { val "$1" | tr -d '\n' | sha256sum | cut -d' ' -f1; }

age-keygen -o "$work/plan.key" 2>/dev/null
age-keygen -o "$work/apply.key" 2>/dev/null
plan_pub=$(age-keygen -y "$work/plan.key")
apply_pub=$(age-keygen -y "$work/apply.key")

# Recipients: inputs for both CI keys, each credential file for its own key only.
python3 - "$plan_pub" "$apply_pub" "$owner_key" <<'EOF'
import sys
plan, apply, owner = sys.argv[1:]
p = '.sops.yaml'; s = open(p).read()
anchor = "  # Everything else (tofu credentials, misc): owner only, all values encrypted.\n"
assert anchor in s and 'creds-plan' not in s
rules = f"""  # OpenTofu in CI (.github/workflows/tofu.yml, scripts/tofu-ci-bootstrap.sh). Inputs (TF_VARs, the state
  # passphrase) for both CI keys; read-only credentials for the plan key, read-write ones for the apply key.
  - path_regex: terraform/secrets\\.sops\\.env$
    age: >-
      {owner},
      {plan},
      {apply}
  - path_regex: terraform/creds-plan\\.sops\\.env$
    age: >-
      {owner},
      {plan}
  - path_regex: terraform/creds-apply\\.sops\\.env$
    age: >-
      {owner},
      {apply}
"""
open(p, 'w').write(s.replace(anchor, rules + anchor, 1))
EOF

# Split terraform/secrets.sops.env: credentials out, TF_VARs stay (and become readable by both CI keys).
sops -d terraform/secrets.sops.env > "$work/secrets.env"
get() { sed -n "s/^$1=//p" "$work/secrets.env"; }
enc() { # <plain file> <target>
  sops encrypt --filename-override "$2" --input-type dotenv --output-type dotenv "$1" > "$2"
}
{
  echo "HCLOUD_TOKEN=$(get HCLOUD_TOKEN)"
  echo "CLOUDFLARE_API_TOKEN=$(val tofu-apply)"
  echo "AWS_ACCESS_KEY_ID=$(s3_id tofu-state-rw)"
  echo "AWS_SECRET_ACCESS_KEY=$(s3_secret tofu-state-rw)"
} > "$work/creds-apply.env"
{
  echo "HCLOUD_TOKEN=$hcloud_ro"
  echo "CLOUDFLARE_API_TOKEN=$(val tofu-plan)"
  echo "AWS_ACCESS_KEY_ID=$(s3_id tofu-state-ro)"
  echo "AWS_SECRET_ACCESS_KEY=$(s3_secret tofu-state-ro)"
} > "$work/creds-plan.env"
{
  echo "NODE_SUDO_PASSWORD=$(get NODE_SUDO_PASSWORD)"
} > "$work/owner.env"
grep -vE '^(HCLOUD_TOKEN|CLOUDFLARE_API_TOKEN|NODE_SUDO_PASSWORD)=' "$work/secrets.env" > "$work/tfvars.env"
enc "$work/creds-apply.env" terraform/creds-apply.sops.env
enc "$work/creds-plan.env" terraform/creds-plan.sops.env
enc "$work/owner.env" terraform/owner.sops.env
enc "$work/tfvars.env" terraform/secrets.sops.env
echo "terraform/*.sops.env written"

# GitHub: the apply key only in environment `production`, which only main may deploy to.
gh api -X PUT "repos/$repo/environments/production" --input - >/dev/null <<'EOF'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
EOF
gh api "repos/$repo/environments/production/deployment-branch-policies" -f name=main -f type=branch >/dev/null 2>&1 || true
gh secret set SOPS_AGE_KEY_APPLY -R "$repo" --env production < "$work/apply.key"
gh secret set SOPS_AGE_KEY_PLAN -R "$repo" < "$work/plan.key"
echo "GitHub: environment production (main only), secrets SOPS_AGE_KEY_APPLY and SOPS_AGE_KEY_PLAN set"

echo
echo "Done. Tell the agent; it commits these files and moves the state to R2."
echo "Afterwards you may delete the old Cloudflare user token OpenTofu used (now replaced by tofu-apply)."

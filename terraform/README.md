# terraform (OpenTofu)

Hetzner Cloud and Cloudflare resources for the platform. Nobody runs `apply` by hand: CI does
(`.github/workflows/tofu.yml`).

- **Flow.** A pull request touching `terraform/` gets a plan as a comment (read-only credentials), the release PR
  `dev -> main` included. Merging the release applies it (environment `production`, main only, read-write
  credentials). `just plan` shows the same plan locally; `just apply-local` is break-glass.
- **State.** Cloudflare R2, bucket `bulbashenko-tofu-state`, key `hel1/terraform.tfstate`, with a lock file. Free
  tier (10 GB, 1M writes a month) against a ~100 KB state and a few operations per run; a Cloudflare budget alert
  mails the owner at $1. Encrypted with pbkdf2 + AES-GCM (`enforced = true`): a plaintext state can never be written.
- **Secrets** (SOPS, see `.sops.yaml`):
  - `secrets.sops.env`: inputs (`TF_VAR_*`, among them the state passphrase); owner and both CI keys.
  - `creds-plan.sops.env`: read-only Hetzner and Cloudflare tokens, read-only R2 credentials; owner and the plan key.
  - `creds-apply.sops.env`: read-write tokens and R2 credentials; owner and the apply key.
  - `owner.sops.env`: `NODE_SUDO_PASSWORD`; owner only.
  The CI keys are GitHub secrets `SOPS_AGE_KEY_PLAN` (repo) and `SOPS_AGE_KEY_APPLY` (environment `production`),
  created once by `just tofu-ci-bootstrap` together with the Cloudflare tokens.
- Existing resources were adopted with `import` blocks (`imports.tf`); after a clean plan those blocks are kept as
  documentation of the adoption and are no-ops.

# terraform (OpenTofu)

Hetzner Cloud and Cloudflare resources for the platform.

- State: `terraform.tfstate`, committed, encrypted (pbkdf2 + AES-GCM, `enforced = true`). A plaintext state can never be written.
- Credentials and the state passphrase: `secrets.sops.env` (`TF_VAR_state_passphrase`, `HCLOUD_TOKEN`, `CLOUDFLARE_API_TOKEN`). The justfile loads them with `sops exec-env`.
- `just plan` anyone with the age key; `just apply` owner only.
- Existing resources were adopted with `import` blocks (`imports.tf`); after a clean plan those blocks are kept as documentation of the adoption and are no-ops.

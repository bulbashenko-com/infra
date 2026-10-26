terraform {
  required_version = ">= 1.10"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.60"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }

  # State lives in Cloudflare R2 (bucket bulbashenko-tofu-state, free tier: a state of ~100 KB and a few
  # operations per run), outside the cluster it describes. It is encrypted with a passphrase kept in
  # secrets.sops.env. Credentials (AWS_*) come from creds-plan.sops.env / creds-apply.sops.env. The lock file
  # (use_lockfile, R2 conditional writes) keeps two applies apart.
  backend "s3" {
    bucket                      = "bulbashenko-tofu-state"
    key                         = "hel1/terraform.tfstate"
    region                      = "auto"
    endpoints                   = { s3 = "https://e6a72845a55a3840d8b52c2d7fdf3004.r2.cloudflarestorage.com" }
    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }
    state {
      method   = method.aes_gcm.main
      enforced = true
    }
    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}

# Tokens come from the environment (HCLOUD_TOKEN, CLOUDFLARE_API_TOKEN): creds-plan.sops.env (read-only, `just plan`
# and pull requests) or creds-apply.sops.env (CI on main, .github/workflows/tofu.yml).
provider "hcloud" {}
provider "cloudflare" {}

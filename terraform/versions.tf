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

  # State lives next to the code and is committed. It is encrypted with a
  # passphrase that itself is kept in secrets.sops.env (age-encrypted).
  backend "local" {
    path = "terraform.tfstate"
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

# Tokens come from the environment (HCLOUD_TOKEN, CLOUDFLARE_API_TOKEN),
# loaded by `just plan` / `just apply` from secrets.sops.env.
provider "hcloud" {}
provider "cloudflare" {}

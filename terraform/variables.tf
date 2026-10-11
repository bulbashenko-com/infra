variable "state_passphrase" {
  description = "Passphrase for state/plan encryption. Set via TF_VAR_state_passphrase from secrets.sops.env."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  type    = string
  default = "e6a72845a55a3840d8b52c2d7fdf3004"
}

variable "cloudflare_zone_id" {
  description = "bulbashenko.com"
  type        = string
  default     = "abb0bea137c9c120a465f8a609c98e02"
}

variable "location" {
  type    = string
  default = "hel1"
}

variable "storage_box_password" {
  description = "Primary Storage Box account password (login is by SSH key; kept for reference). TF_VAR_storage_box_password."
  type        = string
  sensitive   = true
}

variable "owner_ssh_public_key" {
  type    = string
  default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJUPyxCHYtGFd7kthLGvHXBiz4eW8lXLd3XPctyBPgfA bulbashenko"
}

variable "node_password_hash" {
  description = "SHA-512 crypt hash of bulbashenko's sudo password on k3s nodes (plaintext: NODE_SUDO_PASSWORD in secrets.sops.env)."
  type        = string
  sensitive   = true
}

variable "k3s_token" {
  description = "Shared k3s cluster token (server and agents)."
  type        = string
  sensitive   = true
}

variable "k3s_version" {
  type    = string
  default = "v1.36.5+k3s1"
}

variable "tailscale_authkey" {
  description = "One-time Headscale pre-auth key (tag:core, short expiry). Set right before creating a node; empty = join manually."
  type        = string
  sensitive   = true
  default     = ""
}

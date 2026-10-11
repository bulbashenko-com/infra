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

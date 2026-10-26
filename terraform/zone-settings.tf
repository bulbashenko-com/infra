# bulbashenko.com edge settings (answers Cloudflare Security Insights, 2026-10-25): no TLS below 1.2, HTTP always
# redirected to HTTPS, and HSTS on every proxied host, matching the header the site itself sends on the apex.
# DNS-only hosts (mail, hs, ts) are not affected.

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "hsts" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "security_header"
  value = {
    strict_transport_security = {
      enabled            = true
      include_subdomains = true
      max_age            = 63072000
      nosniff            = true
      preload            = true
    }
  }
}

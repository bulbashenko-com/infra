# bulbashenko.com records owned by OpenTofu.
# Mail auth records (MX, SPF, DKIM, mail TXT, _smtp._tls) are owned by Stalwart
# (comment "managed by Stalwart") and are deliberately NOT managed here.

resource "cloudflare_dns_record" "apex_a" {
  comment = "[web] origin: Hetzner CX22. The only IP for proxied hosts"
  content = "65.109.174.215"
  name    = "bulbashenko.com"
  proxied = true
  ttl     = 1
  type    = "A"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "auth_cname" {
  comment = "[auth] Authelia SSO portal and OIDC issuer (public)"
  content = "bulbashenko.com"
  name    = "auth.bulbashenko.com"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "autoconfig" {
  comment = "[mail] Thunderbird autoconfig, routed to Stalwart"
  content = hcloud_primary_ip.core_v4.ip_address
  name    = "autoconfig.bulbashenko.com"
  proxied = true
  ttl     = 1
  type    = "A"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "autodiscover" {
  comment = "[mail] Outlook autodiscover, routed to Stalwart"
  content = hcloud_primary_ip.core_v4.ip_address
  name    = "autodiscover.bulbashenko.com"
  proxied = true
  ttl     = 1
  type    = "A"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "coolify" {
  comment = "[admin] Coolify dashboard, behind Access"
  content = hcloud_primary_ip.core_v4.ip_address
  name    = "coolify.bulbashenko.com"
  proxied = true
  ttl     = 1
  type    = "A"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "dmarc_txt" {
  comment = "[mail] DMARC, manual: p=none, tighten later"
  content = "\"v=DMARC1; p=none; rua=mailto:dmarc@bulbashenko.com; adkim=s; aspf=s\""
  name    = "_dmarc.bulbashenko.com"
  proxied = false
  ttl     = 1
  type    = "TXT"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "hs_a" {
  comment = "[mesh] Headscale control server + DERP on hel1-edge (must not be proxied)"
  content = "62.238.18.202"
  name    = "hs.bulbashenko.com"
  proxied = false
  ttl     = 300
  type    = "A"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "hs_aaaa" {
  comment = "[mesh] Headscale control server + DERP on hel1-edge (must not be proxied)"
  content = "2a01:4f9:c012:b6f5::1"
  name    = "hs.bulbashenko.com"
  proxied = false
  ttl     = 300
  type    = "AAAA"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "mail_a" {
  comment = "[mail] SMTP/IMAP host: DNS-only, IPv4-only on purpose"
  content = "65.109.174.215"
  name    = "mail.bulbashenko.com"
  proxied = false
  ttl     = 1
  type    = "A"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "media_cname" {
  comment = "[storage] Garage website endpoint: media bucket"
  content = "bulbashenko.com"
  name    = "media.bulbashenko.com"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "s3_cname" {
  comment = "[storage] Garage S3 API"
  content = "bulbashenko.com"
  name    = "s3.bulbashenko.com"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "ts_a" {
  comment = "[voice] TeamSpeak 6 on hel1-edge (UDP 9987, TCP 30033; DNS-only)"
  content = "62.238.18.202"
  name    = "ts.bulbashenko.com"
  proxied = false
  ttl     = 300
  type    = "A"
  zone_id = var.cloudflare_zone_id
}

resource "cloudflare_dns_record" "www_cname" {
  comment = "[web] redirects to apex (Coolify)"
  content = "bulbashenko.com"
  name    = "www.bulbashenko.com"
  proxied = true
  ttl     = 1
  type    = "CNAME"
  zone_id = var.cloudflare_zone_id
}

# 2026-10: these stay on core (Coolify/Stalwart) when the apex moves to the tunnel, so they get
# their own A record instead of a CNAME to the apex.
moved {
  from = cloudflare_dns_record.autoconfig_cname
  to   = cloudflare_dns_record.autoconfig
}
moved {
  from = cloudflare_dns_record.autodiscover_cname
  to   = cloudflare_dns_record.autodiscover
}
moved {
  from = cloudflare_dns_record.coolify_cname
  to   = cloudflare_dns_record.coolify
}

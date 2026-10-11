# Cloudflare Tunnel for public web: cloudflared runs in the cluster (2 replicas) and dials out,
# so no node needs public 80/443. Hostnames are routed to the in-cluster Traefik.
resource "cloudflare_zero_trust_tunnel_cloudflared" "hel1" {
  account_id = var.cloudflare_account_id
  name       = "hel1"
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "hel1" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.hel1.id
  config = {
    # Public hostnames are added at cutover, each pointing at Traefik.
    ingress = [
      { service = "http_status:404" },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "hel1" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.hel1.id
}

output "tunnel_hel1_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.hel1.id
}

output "tunnel_hel1_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.hel1.token
  sensitive = true
}

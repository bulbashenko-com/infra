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
    # Every public web hostname goes to the in-cluster Traefik (web entrypoint), which routes by Host.
    ingress = concat(
      [for h in local.tunnel_hostnames : {
        hostname = h
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      }],
      [{ service = "http_status:404" }],
    )
  }
}

locals {
  tunnel_hostnames = [
    "bulbashenko.com",
    "www.bulbashenko.com",
    "auth.bulbashenko.com",
    "media.bulbashenko.com",
    "s3.bulbashenko.com",
  ]
  tunnel_cname = "${cloudflare_zero_trust_tunnel_cloudflared.hel1.id}.cfargotunnel.com"
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

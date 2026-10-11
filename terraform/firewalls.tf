resource "hcloud_firewall" "hel1_core" {
  name = "hel1-core-fw"
  apply_to {
    server = hcloud_server.hel1_core.id
  }
  rule {
    description = "http(s) from Cloudflare"
    direction   = "in"
    port        = "443"
    protocol    = "tcp"
    source_ips  = ["103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22", "104.16.0.0/13", "104.24.0.0/14", "108.162.192.0/18", "131.0.72.0/22", "141.101.64.0/18", "162.158.0.0/15", "172.64.0.0/13", "173.245.48.0/20", "188.114.96.0/20", "190.93.240.0/20", "197.234.240.0/22", "198.41.128.0/17", "2400:cb00::/32", "2405:8100::/32", "2405:b500::/32", "2606:4700::/32", "2803:f800::/32", "2a06:98c0::/29", "2c0f:f248::/32"]
  }
  rule {
    description = "http(s) from Cloudflare"
    direction   = "in"
    port        = "80"
    protocol    = "tcp"
    source_ips  = ["103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22", "104.16.0.0/13", "104.24.0.0/14", "108.162.192.0/18", "131.0.72.0/22", "141.101.64.0/18", "162.158.0.0/15", "172.64.0.0/13", "173.245.48.0/20", "188.114.96.0/20", "190.93.240.0/20", "197.234.240.0/22", "198.41.128.0/17", "2400:cb00::/32", "2405:8100::/32", "2405:b500::/32", "2606:4700::/32", "2803:f800::/32", "2a06:98c0::/29", "2c0f:f248::/32"]
  }
  rule {
    description = "icmp"
    direction   = "in"
    port        = ""
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "imaps"
    direction   = "in"
    port        = "993"
    protocol    = "tcp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "smtp"
    direction   = "in"
    port        = "25"
    protocol    = "tcp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "smtps"
    direction   = "in"
    port        = "465"
    protocol    = "tcp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "ssh"
    direction   = "in"
    port        = "22"
    protocol    = "tcp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "submission"
    direction   = "in"
    port        = "587"
    protocol    = "tcp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "tailscale direct"
    direction   = "in"
    port        = "41641"
    protocol    = "udp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_firewall" "hel1_edge" {
  name = "hel1-edge-fw"
  apply_to {
    server = hcloud_server.hel1_edge.id
  }
  rule {
    description = "STUN (DERP)"
    direction   = "in"
    port        = "3478"
    protocol    = "udp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "http (headscale, LE)"
    direction   = "in"
    port        = "80"
    protocol    = "tcp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "https (headscale, DERP)"
    direction   = "in"
    port        = "443"
    protocol    = "tcp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "icmp"
    direction   = "in"
    port        = ""
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "ssh"
    direction   = "in"
    port        = "22"
    protocol    = "tcp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "tailscale direct"
    direction   = "in"
    port        = "41641"
    protocol    = "udp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "teamspeak file transfer"
    direction   = "in"
    port        = "30033"
    protocol    = "tcp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "teamspeak voice"
    direction   = "in"
    port        = "9987"
    protocol    = "udp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
}

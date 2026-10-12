# hel1-core (mail node): SSH and the public mail ports only. Web reaches the cluster through Cloudflare
# Tunnel and admin UIs through the mesh; node-to-node traffic uses hel1-net (not filtered here).
resource "hcloud_firewall" "hel1_core" {
  name = "hel1-core-fw"
  apply_to {
    server = hcloud_server.hel1_core.id
  }
  rule {
    description = "icmp"
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "ssh"
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "smtp"
    direction   = "in"
    protocol    = "tcp"
    port        = "25"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "smtps (submission over TLS)"
    direction   = "in"
    protocol    = "tcp"
    port        = "465"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
  rule {
    description = "imaps"
    direction   = "in"
    protocol    = "tcp"
    port        = "993"
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

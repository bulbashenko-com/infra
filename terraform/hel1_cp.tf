# hel1-cp: k3s server (control plane, sqlite) for the hel1 cluster. Phase 2 of the GitOps plan.

resource "hcloud_ssh_key" "owner" {
  name       = "bulbashenko"
  public_key = var.owner_ssh_public_key
}

resource "hcloud_firewall" "hel1_cp" {
  name = "hel1-cp-fw"

  # Web reaches the cluster through Cloudflare Tunnel (outbound), admin UIs through the mesh,
  # node-to-node traffic through hel1-net (not filtered by Hetzner firewalls). Nothing else is public.
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
    description = "tailscale direct"
    direction   = "in"
    protocol    = "udp"
    port        = "41641"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "hel1_cp" {
  name         = "hel1-cp"
  server_type  = "cx23"
  image        = "ubuntu-24.04"
  location     = var.location
  backups      = false
  ssh_keys     = [hcloud_ssh_key.owner.id]
  firewall_ids = [hcloud_firewall.hel1_cp.id]
  labels = {
    cluster = "hel1"
    role    = "k3s-server"
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.hel1_net.id
    ip         = local.hel1_cp_private_ip
  }

  user_data = templatefile("${path.module}/cloud-init/k3s-server.yaml.tftpl", {
    hostname          = "hel1-cp"
    private_ip        = local.hel1_cp_private_ip
    pod_cidr          = "10.42.0.0/16"
    password_hash     = var.node_password_hash
    ssh_public_key    = var.owner_ssh_public_key
    k3s_token         = var.k3s_token
    k3s_version       = var.k3s_version
    tailscale_authkey = var.tailscale_authkey
  })

  lifecycle {
    # cloud-init runs once; a changed template means a rebuild, done deliberately.
    ignore_changes = [user_data, image, ssh_keys]
  }

  depends_on = [hcloud_network_subnet.hel1_net]
}

locals {
  hel1_cp_private_ip = "192.168.100.4"
}

output "hel1_cp" {
  value = {
    ipv4       = hcloud_server.hel1_cp.ipv4_address
    ipv6       = hcloud_server.hel1_cp.ipv6_address
    private_ip = local.hel1_cp_private_ip
  }
}

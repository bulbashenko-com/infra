# Mail IP: PTR mail.bulbashenko.com, SPF and sender reputation are tied to it.
# It must survive the server (rebuild, replacement, move to another node).
resource "hcloud_primary_ip" "core_v4" {
  assignee_id       = hcloud_server.hel1_core.id
  assignee_type     = "server"
  auto_delete       = false
  delete_protection = true
  name              = "bulbashenko.com"
  type              = "ipv4"

  lifecycle {
    prevent_destroy = true
  }
}

# Mail IP: PTR mail.bulbashenko.com, SPF and sender reputation are tied to it.
# It must survive the server (rebuild, replacement, move to another node).
resource "hcloud_primary_ip" "core_v6" {
  assignee_id       = hcloud_server.hel1_core.id
  assignee_type     = "server"
  auto_delete       = false
  delete_protection = true
  name              = "bulbashenko.com (ipv6)"
  type              = "ipv6"

  lifecycle {
    prevent_destroy = true
  }
}

# hel1-edge IP: DNS for hs. (Headscale, DNS-only) and ts. (TeamSpeak) points here; it must survive
# the server being recreated as a k3s agent.
resource "hcloud_primary_ip" "edge_v4" {
  location          = var.location
  assignee_type     = "server"
  auto_delete       = false
  delete_protection = true
  name              = "primary_ip-135832240"
  type              = "ipv4"

  lifecycle {
    prevent_destroy = true
    # Assigned through hcloud_server.hel1_edge.public_net.
    ignore_changes = [assignee_id]
  }
}

# hel1-edge IP: DNS for hs. (Headscale, DNS-only) and ts. (TeamSpeak) points here; it must survive
# the server being recreated as a k3s agent.
resource "hcloud_primary_ip" "edge_v6" {
  location          = var.location
  assignee_type     = "server"
  auto_delete       = false
  delete_protection = true
  name              = "primary_ip-135832241"
  type              = "ipv6"

  lifecycle {
    prevent_destroy = true
    # Assigned through hcloud_server.hel1_edge.public_net.
    ignore_changes = [assignee_id]
  }
}

resource "hcloud_server" "hel1_core" {
  backups            = true
  delete_protection  = false
  image              = "ubuntu-24.04"
  location           = "hel1"
  name               = "hel1-core"
  rebuild_protection = false
  server_type        = "cx22"

  lifecycle {
    # Built before this repo by hand/cloud-init; rebuilds happen via new resources, not drift fixes.
    ignore_changes = [image, user_data, ssh_keys]
  }
}

# hel1-edge: k3s agent (role=edge). Owns the public IP that hs. (Headscale) and ts. (TeamSpeak) point at;
# the primary IPs are separate, protected resources, so the server can be recreated without losing them.
resource "hcloud_server" "hel1_edge" {
  name        = "hel1-edge"
  server_type = "cx23"
  image       = "ubuntu-24.04"
  location    = var.location
  backups     = true
  ssh_keys    = [hcloud_ssh_key.owner.id]
  labels = {
    cluster = "hel1"
    role    = "k3s-agent-edge"
  }

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.edge_v4.id
    ipv6_enabled = true
    ipv6         = hcloud_primary_ip.edge_v6.id
  }

  network {
    network_id = hcloud_network.hel1_net.id
    ip         = "192.168.100.3"
  }

  user_data = templatefile("${path.module}/cloud-init/k3s-agent.yaml.tftpl", {
    hostname       = "hel1-edge"
    role           = "edge"
    private_ip     = "192.168.100.3"
    server_ip      = local.hel1_cp_private_ip
    pod_cidr       = "10.42.0.0/16"
    password_hash  = var.node_password_hash
    ssh_public_key = var.owner_ssh_public_key
    k3s_token      = var.k3s_token
    k3s_version    = var.k3s_version
  })

  depends_on = [hcloud_network_subnet.hel1_net]
}

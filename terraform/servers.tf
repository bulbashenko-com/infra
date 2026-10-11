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

resource "hcloud_primary_ip" "edge_v4" {
  assignee_id       = hcloud_server.hel1_edge.id
  assignee_type     = "server"
  auto_delete       = true
  delete_protection = false
  name              = "primary_ip-135832240"
  type              = "ipv4"
}

resource "hcloud_primary_ip" "edge_v6" {
  assignee_id       = hcloud_server.hel1_edge.id
  assignee_type     = "server"
  auto_delete       = true
  delete_protection = false
  name              = "primary_ip-135832241"
  type              = "ipv6"
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

resource "hcloud_server" "hel1_edge" {
  backups            = true
  delete_protection  = false
  image              = "ubuntu-24.04"
  location           = "hel1"
  name               = "hel1-edge"
  rebuild_protection = false
  server_type        = "cx23"

  lifecycle {
    # Built before this repo by hand/cloud-init; rebuilds happen via new resources, not drift fixes.
    ignore_changes = [image, user_data, ssh_keys]
  }
}

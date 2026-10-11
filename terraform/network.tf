resource "hcloud_network_subnet" "hel1_net" {
  ip_range     = "192.168.100.0/24"
  network_id   = hcloud_network.hel1_net.id
  network_zone = "eu-central"
  type         = "cloud"
}

resource "hcloud_network" "hel1_net" {
  delete_protection        = false
  expose_routes_to_vswitch = false
  ip_range                 = "192.168.100.0/24"
  name                     = "hel1-net"
}

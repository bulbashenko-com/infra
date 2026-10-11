# Adoption of resources that existed before this repo (2026-10-11).
# Config for them was generated with `tofu plan -generate-config-out` and then cleaned up.

# --- Hetzner ---------------------------------------------------------------
import {
  to = hcloud_network.hel1_net
  id = "12720454"
}
import {
  to = hcloud_network_subnet.hel1_net
  id = "12720454-192.168.100.0/24"
}
import {
  to = hcloud_firewall.hel1_core
  id = "11729676"
}
import {
  to = hcloud_firewall.hel1_edge
  id = "11756440"
}
import {
  to = hcloud_primary_ip.core_v4
  id = "85070361"
}
import {
  to = hcloud_primary_ip.core_v6
  id = "85070362"
}
import {
  to = hcloud_primary_ip.edge_v4
  id = "135832240"
}
import {
  to = hcloud_primary_ip.edge_v6
  id = "135832241"
}
import {
  to = hcloud_server.hel1_core
  id = "61920492"
}
import {
  to = hcloud_server.hel1_edge
  id = "141245160"
}
import {
  to = hcloud_storage_box.backups
  id = "671089"
}

# --- Cloudflare DNS (bulbashenko.com) --------------------------------------
import {
  to = cloudflare_dns_record.auth_cname
  id = "abb0bea137c9c120a465f8a609c98e02/f59b2ffd257dbceda7ea30e146d091b9"
}
import {
  to = cloudflare_dns_record.autoconfig_cname
  id = "abb0bea137c9c120a465f8a609c98e02/947cd54716d1997584f854961a10e5e9"
}
import {
  to = cloudflare_dns_record.autodiscover_cname
  id = "abb0bea137c9c120a465f8a609c98e02/5ac30afb2c0296d395b810b2e071cb10"
}
import {
  to = cloudflare_dns_record.apex_a
  id = "abb0bea137c9c120a465f8a609c98e02/2616dc7140901129d097e74d7ab28742"
}
import {
  to = cloudflare_dns_record.apex_mx
  id = "abb0bea137c9c120a465f8a609c98e02/6ea15812aade304a1d2e14e7a1559072"
}
import {
  to = cloudflare_dns_record.apex_txt
  id = "abb0bea137c9c120a465f8a609c98e02/2765f86424d5db7ed97f7588cc09e369"
}
import {
  to = cloudflare_dns_record.coolify_cname
  id = "abb0bea137c9c120a465f8a609c98e02/cdbcf25c8a31f502faed0a006a57f59f"
}
import {
  to = cloudflare_dns_record.dmarc_txt
  id = "abb0bea137c9c120a465f8a609c98e02/af46f9e284d9477708a188e2fb0e0ebd"
}
import {
  to = cloudflare_dns_record.hs_aaaa
  id = "abb0bea137c9c120a465f8a609c98e02/c1a697dc90d84c504d7f09c4b35d239b"
}
import {
  to = cloudflare_dns_record.hs_a
  id = "abb0bea137c9c120a465f8a609c98e02/bb7152e7aaf3ecfbc886dfb3aa37bd75"
}
import {
  to = cloudflare_dns_record.mail_a
  id = "abb0bea137c9c120a465f8a609c98e02/721f85174f0ec98854684ea54aac69e9"
}
import {
  to = cloudflare_dns_record.mail_txt
  id = "abb0bea137c9c120a465f8a609c98e02/fbf5b656292f74fe2c67730b2a857170"
}
import {
  to = cloudflare_dns_record.media_cname
  id = "abb0bea137c9c120a465f8a609c98e02/f05d0bb378a66e791a18bb657c0620e2"
}
import {
  to = cloudflare_dns_record.s3_cname
  id = "abb0bea137c9c120a465f8a609c98e02/4e0d61bea58fe92846de93093268b988"
}
import {
  to = cloudflare_dns_record.smtp__tls_txt
  id = "abb0bea137c9c120a465f8a609c98e02/f98b049f6a693116b65d1d74f46004e3"
}
import {
  to = cloudflare_dns_record.ts_a
  id = "abb0bea137c9c120a465f8a609c98e02/0b5947c7d53d3f923da1eac46191e688"
}
import {
  to = cloudflare_dns_record.v1_ed25519_20261006__domainkey_txt
  id = "abb0bea137c9c120a465f8a609c98e02/b3fd5fd0ce138dff62de52fa5690e5e4"
}
import {
  to = cloudflare_dns_record.v1_rsa_20261006__domainkey_txt
  id = "abb0bea137c9c120a465f8a609c98e02/5e51f5817d1bf5703040d85d7844f616"
}
import {
  to = cloudflare_dns_record.www_cname
  id = "abb0bea137c9c120a465f8a609c98e02/23d2773cdbcce9993d4c7ab35099e435"
}

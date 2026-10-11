resource "hcloud_storage_box" "backups" {
  access_settings = {
    reachable_externally = true
    samba_enabled        = false
    ssh_enabled          = true
    webdav_enabled       = false
    zfs_enabled          = false
  }
  delete_protection = true
  location          = "hel1"
  name              = "storage-box-1"
  password          = var.storage_box_password
  storage_box_type  = "bx11"

  lifecycle {
    # The API cannot read the password back; it is kept in secrets.sops.env for reference only.
    ignore_changes = [password]
  }
}

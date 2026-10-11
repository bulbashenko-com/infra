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
  # Daily snapshots guard the off-site copy against deletion or corruption by the writer itself.
  snapshot_plan = {
    hour          = 5
    minute        = 0
    max_snapshots = 7
  }

  lifecycle {
    # The API cannot read the password back; it is kept in secrets.sops.env for reference only.
    ignore_changes = [password]
  }
}

# Off-site copy of the cluster's backups (CNPG base backups + WAL, media), written by the
# offsite-backup CronJob over SFTP and encrypted client-side with rclone crypt.
resource "hcloud_storage_box_subaccount" "hel1_backups" {
  storage_box_id = hcloud_storage_box.backups.id
  home_directory = "hel1-backups"
  password       = var.storage_box_hel1_password
  description    = "hel1 cluster off-site backups (rclone crypt)"
  access_settings = {
    ssh_enabled          = true
    samba_enabled        = false
    webdav_enabled       = false
    reachable_externally = true
    readonly             = false
  }
  lifecycle {
    ignore_changes = [password]
  }
}

output "storage_box_hel1_backups_username" {
  value = hcloud_storage_box_subaccount.hel1_backups.username
}

#!/bin/sh
# Encrypted off-site copy: Garage buckets -> Storage Box subaccount (SFTP) through rclone crypt.
# Names and contents are encrypted; Storage Box snapshots keep 7 daily versions of the result.
set -eu
export RCLONE_CONFIG_BOX_PASS="$(rclone obscure "$BOX_PASSWORD")"
export RCLONE_CONFIG_SAFE_PASSWORD="$(rclone obscure "$CRYPT_PASSWORD")"
export RCLONE_CONFIG_SAFE_PASSWORD2="$(rclone obscure "$CRYPT_SALT")"
for b in cnpg-backups media; do
  echo "== $b"
  rclone sync "garage:$b" "safe:$b" --config /dev/null --stats-one-line --stats 30s -v
done
echo "off-site backup done"

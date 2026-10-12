#!/bin/sh
# Step 1 of the drill: pull the CNPG backups from the Storage Box (as an outage would force us to)
# into the Garage bucket `drill`, keeping barman's layout (pg/base, pg/wals).
set -eu
export RCLONE_CONFIG_BOX_PASS="$(rclone obscure "$BOX_PASSWORD")"
export RCLONE_CONFIG_SAFE_PASSWORD="$(rclone obscure "$CRYPT_PASSWORD")"
export RCLONE_CONFIG_SAFE_PASSWORD2="$(rclone obscure "$CRYPT_SALT")"
until rclone --config /dev/null lsf garage:drill >/dev/null 2>&1; do echo "waiting for bucket drill"; sleep 5; done
rclone --config /dev/null sync safe:cnpg-backups garage:drill --stats-one-line --stats 30s -v
rclone --config /dev/null size garage:drill
echo "drill fetch done"

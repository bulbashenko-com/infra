#!/bin/sh
# Copy every bucket from the single-node Garage into garage-ha. Each bucket uses its own read-write key,
# which exists with the same ID and secret on both clusters. Copy only, never deletes: safe to re-run.
set -eu
copy() { # bucket keyId keySecret
  export RCLONE_CONFIG_OLD_ACCESS_KEY_ID="$2" RCLONE_CONFIG_OLD_SECRET_ACCESS_KEY="$3"
  export RCLONE_CONFIG_NEW_ACCESS_KEY_ID="$2" RCLONE_CONFIG_NEW_SECRET_ACCESS_KEY="$3"
  # garage-ha-bootstrap creates the bucket and grants the key; wait for it.
  until rclone lsf "new:$1" --max-depth 1 >/dev/null 2>&1; do echo "waiting for new:$1"; sleep 5; done
  rclone copy "old:$1" "new:$1" --metadata --checksum --transfers 8 --stats-one-line --stats 30s
  echo "$1: old $(rclone size "old:$1" | tr '\n' ' ')"
  echo "$1: new $(rclone size "new:$1" | tr '\n' ' ')"
}
copy media "$KEY_APP_MEDIA_ID" "$KEY_APP_MEDIA_SECRET"
copy cnpg-backups "$KEY_CNPG_ID" "$KEY_CNPG_SECRET"
copy restore "$KEY_RESTORE_ID" "$KEY_RESTORE_SECRET"
echo "garage migrate done"

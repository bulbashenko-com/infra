#!/bin/sh
# Fill an empty data volume once from the Garage bucket "restore" ($ARCHIVE, a .tar.gz of the old volume).
# Refuses to start on an empty volume without the archive: a fresh Headscale would mint new keys and every
# device would have to register again.
set -eu
if [ -f /data/.restored ]; then echo "volume already initialised"; exit 0; fi
if [ -n "$(ls -A /data 2>/dev/null)" ]; then echo "volume not empty, keeping it"; touch /data/.restored; exit 0; fi
export RCLONE_CONFIG_G_TYPE=s3 RCLONE_CONFIG_G_PROVIDER=Other RCLONE_CONFIG_G_REGION=garage \
  RCLONE_CONFIG_G_ENDPOINT=http://garage.data.svc.cluster.local:3900 RCLONE_CONFIG_G_FORCE_PATH_STYLE=true \
  RCLONE_CONFIG_G_ACCESS_KEY_ID="$RESTORE_S3_ACCESS_KEY_ID" RCLONE_CONFIG_G_SECRET_ACCESS_KEY="$RESTORE_S3_SECRET_ACCESS_KEY"
if ! rclone --config /dev/null lsf "g:restore/$ARCHIVE" | grep -q .; then
  echo "archive restore/$ARCHIVE not found; refusing to start with an empty volume" >&2
  exit 1
fi
rclone --config /dev/null cat "g:restore/$ARCHIVE" | tar -xzf - -C /data
touch /data/.restored
echo "restored $ARCHIVE:"; ls -la /data

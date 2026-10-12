#!/bin/sh
# One-time import of the Coolify Stalwart export (restore/stalwart-export.tar.gz) into Postgres.
set -eu
export RCLONE_CONFIG_G_TYPE=s3 RCLONE_CONFIG_G_PROVIDER=Other RCLONE_CONFIG_G_REGION=garage \
  RCLONE_CONFIG_G_ENDPOINT=http://garage.data.svc.cluster.local:3900 RCLONE_CONFIG_G_FORCE_PATH_STYLE=true \
  RCLONE_CONFIG_G_ACCESS_KEY_ID="$RESTORE_S3_ACCESS_KEY_ID" RCLONE_CONFIG_G_SECRET_ACCESS_KEY="$RESTORE_S3_SECRET_ACCESS_KEY"
rclone --config /dev/null cat g:restore/stalwart-export.tar.gz | tar -xzf - -C /export
echo "export unpacked:"; ls -la /export

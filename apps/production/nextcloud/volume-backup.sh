#!/bin/sh
# Nightly backup of an app volume into the Garage bucket "restore" as $ARCHIVE (what restore-once reads).
# Root only installs the tools; the volume is read as the app's own user ($RUN_AS) so SQLite never leaves
# root-owned -wal/-shm files behind. Databases go through the online backup API (consistent while running).
set -eu
apk add --no-cache -q sqlite rclone tar su-exec >/dev/null
exec su-exec "$RUN_AS" sh -eu -c '
snap=/tmp/snap; rm -rf "$snap"; mkdir -p "$snap"
cd /data
find . -mindepth 1 -type d | while read -r d; do mkdir -p "$snap/$d"; done
find . -type f ! -name .restored | while read -r f; do
  case "$f" in
    *.sqlite|*.sqlitedb|*.db) sqlite3 "$f" ".backup '"'"'$snap/$f'"'"'" ;;
    *-wal|*-shm|*-journal) ;;  # part of the database backup above
    *) cp -p "$f" "$snap/$f" ;;
  esac
done
tar -czf /tmp/archive.tar.gz -C "$snap" .
export RCLONE_CONFIG_G_TYPE=s3 RCLONE_CONFIG_G_PROVIDER=Other RCLONE_CONFIG_G_REGION=garage \
  RCLONE_CONFIG_G_ENDPOINT=http://garage.data.svc.cluster.local:3900 RCLONE_CONFIG_G_FORCE_PATH_STYLE=true \
  RCLONE_CONFIG_G_ACCESS_KEY_ID="$RESTORE_S3_ACCESS_KEY_ID" RCLONE_CONFIG_G_SECRET_ACCESS_KEY="$RESTORE_S3_SECRET_ACCESS_KEY"
rclone --config /dev/null copyto /tmp/archive.tar.gz "g:restore/$ARCHIVE"
echo "backed up $(tar -tzf /tmp/archive.tar.gz | wc -l) entries, $(du -h /tmp/archive.tar.gz | cut -f1) -> restore/$ARCHIVE"
'

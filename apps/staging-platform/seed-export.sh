#!/bin/sh
# Production side of the staging refresh: dump the site's content database for staging to restore
# (apps/staging/site/refresh.sh). Schema plus data, without the admin sessions; ownership and grants dropped,
# so the dump restores as the staging role. Runs as two containers sharing /work: pg_dump, then the upload.
set -eu
case "$1" in
  dump)
    pg_dump --format=custom --no-owner --no-privileges --exclude-table-data='"Session"' --file=/work/site.dump
    ls -l /work/site.dump ;;
  upload)
    rclone --config /dev/null copyto /work/site.dump garage:staging-seed/site.dump -v
    echo "seed exported" ;;
esac

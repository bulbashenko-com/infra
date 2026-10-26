#!/bin/sh
# Staging side of the refresh: restore the content dump that production exports nightly (apps/staging-platform)
# into bulbashenko_staging, and mirror the media bucket. Admin sessions are not in the dump; everything else the
# site stores is replaced. Two containers sharing /work: fetch (rclone), then restore (pg_restore).
# Runs nightly at 03:15 UTC (CronJob) and whenever REVISION in kustomization.yaml changes (`just staging-refresh`).
set -eu
case "$1" in
  fetch)
    if ! rclone --config /dev/null lsf garage:staging-seed/site.dump >/dev/null 2>&1; then
      echo "no seed yet (production exports it nightly); nothing to restore"; touch /work/none; exit 0
    fi
    rclone --config /dev/null copyto garage:staging-seed/site.dump /work/site.dump -v
    rclone --config /dev/null sync garage:media garage:media-staging --stats-one-line -v ;;
  restore)
    [ ! -e /work/none ] || exit 0
    pg_restore --clean --if-exists --no-owner --no-privileges --single-transaction --dbname="$DATABASE_URL" /work/site.dump
    echo "staging restored from $(date -u -r /work/site.dump +%FT%TZ)" ;;
esac

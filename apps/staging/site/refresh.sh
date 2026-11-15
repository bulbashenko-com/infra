#!/bin/sh
# Staging side of the refresh: restore the content dump that production exports nightly (apps/staging-platform)
# into bulbashenko_staging. Admin sessions are not in the dump; everything else the
# site stores is replaced. Containers sharing /work: fetch (rclone), restore (pg_restore), then the site's own
# migrate image brings the restored schema to staging's version (refresh.yaml).
# Runs nightly at 03:15 UTC (CronJob) and whenever REVISION in kustomization.yaml changes (`just staging-refresh`).
set -eu
case "$1" in
  fetch)
    if ! rclone --config /dev/null lsf garage:staging-seed/site.dump >/dev/null 2>&1; then
      echo "no seed yet (production exports it nightly); nothing to restore"; touch /work/none; exit 0
    fi
    rclone --config /dev/null copyto garage:staging-seed/site.dump /work/site.dump -v ;;
  restore)
    [ ! -e /work/none ] || exit 0
    # An exact copy of production, migration history included: everything in the schema goes first. A --clean
    # restore dropped only what the dump contains, so staging kept its own _prisma_migrations next to production's
    # older tables, and the migrate step then saw drift instead of migrations to apply.
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c 'DROP SCHEMA public CASCADE' -c 'CREATE SCHEMA public'
    pg_restore --no-owner --no-privileges --single-transaction --dbname="$DATABASE_URL" /work/site.dump
    echo "staging restored from $(date -u -r /work/site.dump +%FT%TZ)" ;;
esac

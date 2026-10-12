#!/bin/sh
# Encrypted off-site copy: Garage buckets -> Storage Box subaccount (SFTP) through rclone crypt.
# Names and contents are encrypted. Fast NVMe (Garage) keeps the live data and a short history;
# the Storage Box keeps the long history, and its snapshots keep 7 daily versions of all of it.
set -eu
export RCLONE_CONFIG_BOX_PASS="$(rclone obscure "$BOX_PASSWORD")"
export RCLONE_CONFIG_SAFE_PASSWORD="$(rclone obscure "$CRYPT_PASSWORD")"
export RCLONE_CONFIG_SAFE_PASSWORD2="$(rclone obscure "$CRYPT_SALT")"
KEEP=60d
r() { rclone "$@" --config /dev/null --stats-one-line --stats 30s -v; }

echo "== media (mirror)"
r sync garage:media safe:media

# Garage keeps 7 days (retentionPolicy in data/backup.yaml); here nothing is deleted when Garage drops it,
# so point-in-time recovery reaches back $KEEP (copy the prefix back into a bucket to restore from it).
echo "== cnpg-backups (accumulate, prune after $KEEP)"
r copy garage:cnpg-backups safe:cnpg-backups
r delete safe:cnpg-backups --min-age "$KEEP" --rmdirs

# Volume archives are overwritten nightly in Garage; keep each night's copy here.
echo "== restore (latest mirror + dated copies of tonight's archives, pruned after $KEEP)"
r sync garage:restore safe:restore
r copy garage:restore "safe:restore-daily/$(date -u +%F)" --max-age 24h
r delete safe:restore-daily --min-age "$KEEP" --rmdirs
echo "off-site backup done"

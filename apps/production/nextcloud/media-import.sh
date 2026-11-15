#!/bin/sh
# One-time import of the site's gallery from the old Garage bucket `media` into the Team folder Site/Gallery
# (bulbashenko-com/site docs/deployment.md, Media). Copies only the files the site still uses (GalleryImage rows and
# the profile photo): the old admin panel deleted rows but left the objects. Names stay the same, which is how the
# site carries captions, order and the profile photo over. Safe to re-run: files already there are skipped.
set -eu
apk add --no-cache rclone curl postgresql17-client >/dev/null
NC="http://nextcloud.nextcloud.svc.cluster.local:8080/remote.php/dav/files/$NC_USER"
auth="$NC_USER:$NC_PASSWORD"

# The Team folder comes from the Nextcloud start hook (release.yaml). Never create Site here: a plain folder of that
# name would hide the Team folder from this user.
mount_type() {
  curl -fsS -u "$auth" -X PROPFIND -H 'Depth: 0' "$NC/Site/" --data \
    '<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:nc="http://nextcloud.org/ns"><d:prop><nc:mount-type/></d:prop></d:propfind>' \
    2>/dev/null | grep -o '<nc:mount-type>[a-z]*' | cut -d'>' -f2 || true
}
until [ "$(mount_type)" = group ]; do echo "waiting for the Team folder Site"; sleep 20; done
for dir in Gallery Files; do
  # 201 created, 405 already there.
  code=$(curl -s -o /dev/null -w '%{http_code}' -u "$auth" -X MKCOL "$NC/Site/$dir/")
  case "$code" in 201|405) ;; *) echo "MKCOL Site/$dir: HTTP $code"; exit 1 ;; esac
done

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -Atc \
  'SELECT src FROM "GalleryImage" UNION SELECT photo FROM "Profile" WHERE photo IS NOT NULL' |
  sed -n 's|.*/gallery/\([^/?#]*\).*|\1|p' | sort -u > /tmp/in-use.txt
echo "$(wc -l < /tmp/in-use.txt) files in use"

export RCLONE_CONFIG_GARAGE_TYPE=s3 RCLONE_CONFIG_GARAGE_PROVIDER=Other \
  RCLONE_CONFIG_GARAGE_ENDPOINT=http://garage.data.svc.cluster.local:3900 RCLONE_CONFIG_GARAGE_REGION=garage \
  RCLONE_CONFIG_GARAGE_FORCE_PATH_STYLE=true \
  RCLONE_CONFIG_GARAGE_ACCESS_KEY_ID="$GARAGE_KEY_ID" RCLONE_CONFIG_GARAGE_SECRET_ACCESS_KEY="$GARAGE_KEY_SECRET"
export RCLONE_CONFIG_NC_TYPE=webdav RCLONE_CONFIG_NC_VENDOR=nextcloud RCLONE_CONFIG_NC_URL="$NC" \
  RCLONE_CONFIG_NC_USER="$NC_USER" RCLONE_CONFIG_NC_PASS="$(rclone obscure "$NC_PASSWORD")"
rclone --config /dev/null copy garage:media/gallery nc:Site/Gallery \
  --files-from /tmp/in-use.txt --no-traverse --ignore-existing --stats-one-line -v
echo "import done: $(rclone --config /dev/null lsf nc:Site/Gallery | wc -l) files in Site/Gallery"

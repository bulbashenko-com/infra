#!/bin/sh
# Idempotent Garage setup through the admin API v2: layout, buckets, aliases, website, imported keys.
# Safe to re-run; it only creates what is missing.
set -eu
apk add --no-cache curl jq >/dev/null
A="http://garage:3903"
H="Authorization: Bearer ${GARAGE_ADMIN_TOKEN}"
get()  { curl -fsS -H "$H" "$A$1"; }
post() { curl -fsS -H "$H" -H 'Content-Type: application/json' -X POST "$A$1" -d "$2"; }

until curl -fsS "$A/health" >/dev/null 2>&1; do echo "waiting for garage"; sleep 3; done

# Layout: assign this single node once (zone hel1, 10 GiB).
if [ "$(get /v2/GetClusterLayout | jq '.roles | length')" = 0 ]; then
  node=$(get /v2/GetClusterStatus | jq -r '.nodes[0].id')
  post /v2/UpdateClusterLayout "{\"roles\":[{\"id\":\"$node\",\"zone\":\"hel1\",\"capacity\":10737418240,\"tags\":[]}]}" >/dev/null
  v=$(get /v2/GetClusterLayout | jq '.version + 1')
  post /v2/ApplyClusterLayout "{\"version\":$v}" >/dev/null
  echo "layout applied (v$v)"
fi

bucket_id() { curl -fsS -H "$H" "$A/v2/GetBucketInfo?globalAlias=$1" 2>/dev/null | jq -r '.id // empty'; }

ensure_bucket() { # name [extra alias]
  id=$(bucket_id "$1")
  if [ -z "$id" ]; then id=$(post /v2/CreateBucket "{\"globalAlias\":\"$1\"}" | jq -r .id); echo "bucket $1 created"; fi
  if [ -n "${2:-}" ] && [ -z "$(bucket_id "$2")" ]; then
    post /v2/AddBucketAlias "{\"bucketId\":\"$id\",\"globalAlias\":\"$2\"}" >/dev/null; echo "alias $2 -> $1"
  fi
  echo "$id"
}

ensure_key() { # name id secret
  if ! curl -fsS -H "$H" "$A/v2/GetKeyInfo?id=$2" >/dev/null 2>&1; then
    post /v2/ImportKey "{\"name\":\"$1\",\"accessKeyId\":\"$2\",\"secretAccessKey\":\"$3\"}" >/dev/null; echo "key $1 imported"
  fi
}

allow() { # bucketId keyId
  post /v2/AllowBucketKey "{\"bucketId\":\"$1\",\"accessKeyId\":\"$2\",\"permissions\":{\"read\":true,\"write\":true,\"owner\":false}}" >/dev/null
}

media=$(ensure_bucket media media.bulbashenko.com | tail -1)
post "/v2/UpdateBucket?id=$media" '{"websiteAccess":{"enabled":true,"indexDocument":"index.html"}}' >/dev/null

ensure_key app-media "$KEY_APP_MEDIA_ID" "$KEY_APP_MEDIA_SECRET"
ensure_key ci-skull "$KEY_CI_SKULL_ID" "$KEY_CI_SKULL_SECRET"
allow "$media" "$KEY_APP_MEDIA_ID"
allow "$media" "$KEY_CI_SKULL_ID"
echo "garage bootstrap done"

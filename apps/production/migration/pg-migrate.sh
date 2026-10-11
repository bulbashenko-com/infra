#!/bin/sh
# Copy the four databases from the Coolify Postgres (core, via hel1-net) into CNPG `pg`.
# Objects end up owned by each database's role; extensions are created by the superuser first.
set -eu
SRC="host=192.168.100.2 port=5432 user=$SRC_PG_USER sslmode=disable"
DST="host=pg-rw user=$DST_PG_USER sslmode=require"
export PGCONNECT_TIMEOUT=10
for pair in bulbashenko:bulbashenko kratos:kratos hydra:hydra keto:keto; do
  db=${pair%%:*}; owner=${pair##*:}
  echo "== $db (owner $owner)"
  PGPASSWORD=$SRC_PG_PASSWORD pg_dump "$SRC dbname=$db" -Fc --no-owner --no-privileges -f "/work/$db.dump"
  exts=$(PGPASSWORD=$SRC_PG_PASSWORD psql "$SRC dbname=$db" -Atc "select extname from pg_extension where extname <> 'plpgsql'")
  for e in $exts; do
    PGPASSWORD=$DST_PG_PASSWORD psql "$DST dbname=$db" -v ON_ERROR_STOP=1 -qc "create extension if not exists \"$e\""
  done
  pg_restore -l "/work/$db.dump" | grep -vE ' EXTENSION | COMMENT - EXTENSION ' > "/work/$db.list"
  PGPASSWORD=$DST_PG_PASSWORD pg_restore -d "$DST dbname=$db" --clean --if-exists --no-owner --no-privileges \
    --role="$owner" --exit-on-error -L "/work/$db.list" "/work/$db.dump"
  src=$(PGPASSWORD=$SRC_PG_PASSWORD psql "$SRC dbname=$db" -Atc "select count(*) from information_schema.tables where table_schema not in ('pg_catalog','information_schema')")
  dst=$(PGPASSWORD=$DST_PG_PASSWORD psql "$DST dbname=$db" -Atc "select count(*) from information_schema.tables where table_schema not in ('pg_catalog','information_schema')")
  echo "   tables: source=$src target=$dst"
  [ "$src" = "$dst" ] || { echo "table count mismatch in $db"; exit 1; }
done
echo "postgres migration done"

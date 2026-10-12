#!/bin/sh
# Same report from production (pg-rw) and the drill (pg-drill-rw), then the diff.
set -eu
report() {
  psql -h "$1" -XAtq -c "SELECT 'db ' || datname || ' ' || pg_size_pretty(pg_database_size(datname))
                          FROM pg_database WHERE NOT datistemplate ORDER BY 1"
  psql -h "$1" -XAtq <<'SQL'
SELECT format('SELECT %L || '' '' || count(*) FROM %I.%I', 'rows ' || schemaname || '.' || tablename, schemaname, tablename)
FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema') ORDER BY 1 \gexec
SQL
}
until psql -h pg-drill-rw -XAtq -c 'select 1' >/dev/null 2>&1; do echo "waiting for pg-drill"; sleep 10; done
report pg-rw > /tmp/prod
report pg-drill-rw > /tmp/drill
echo "== production";  cat /tmp/prod
echo "== drill";       cat /tmp/drill
if diff -u /tmp/prod /tmp/drill; then echo "DRILL OK: identical"; else echo "DRILL: differences above"; fi

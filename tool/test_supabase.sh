#!/bin/bash
# Проверка миграций Supabase на локальном Postgres 16.
#
# Поднимает временную базу, кладёт заглушку схемы auth
# (supabase/tests/auth_stub.sql), применяет все миграции по порядку и
# прогоняет supabase/tests/*_test.sql. Живую базу не трогает.
#
#   tool/test_supabase.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
DIR=${PGTEST_DIR:-/tmp/pgtest}
PORT=${PGTEST_PORT:-55432}
RUN_AS=${PGTEST_USER:-postgres}

if ! psql -h "$DIR" -p "$PORT" -U postgres -c 'select 1' >/dev/null 2>&1; then
  rm -rf "$DIR"; mkdir -p "$DIR"; chown "$RUN_AS" "$DIR"
  su "$RUN_AS" -s /bin/bash -c "$PGBIN/initdb -D $DIR/data -A trust -U postgres >/dev/null && \
    $PGBIN/pg_ctl -D $DIR/data -o '-p $PORT -k $DIR' -l $DIR/log start >/dev/null"
  sleep 2
fi

P="psql -h $DIR -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
$P -c 'drop database if exists tt_test' -c 'create database tt_test' >/dev/null
$P -d tt_test -f "$ROOT/supabase/tests/auth_stub.sql" >/dev/null
for f in "$ROOT"/supabase/migrations/*.sql; do
  $P -d tt_test -f "$f" >/dev/null 2>&1 || { echo "Миграция упала: $f"; $P -d tt_test -f "$f"; exit 1; }
done
for t in "$ROOT"/supabase/tests/*_test.sql; do
  echo "== $(basename "$t")"
  $P -d tt_test -At -f "$t"
done

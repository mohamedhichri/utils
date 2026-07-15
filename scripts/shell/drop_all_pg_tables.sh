#!/bin/bash
#
# drop_all_tables.sh
# Drops all tables in the 'public' schema of the target PostgreSQL database.
# Does NOT drop the database itself - only the tables inside it.
#
set -euo pipefail

PGSQL_HOST=localhost
PGSQL_PORT=5432
PGSQL_DATABASE=dssdesigndb
PGSQL_USER=dssruntimedbuser
PGSQL_PWD=D@taikuP4ssF0rDB!

export PGPASSWORD="${PGSQL_PWD}"

echo "=========================================="
echo " Drop ALL tables in database: ${PGSQL_DATABASE}"
echo " Host: ${PGSQL_HOST}:${PGSQL_PORT}"
echo " User: ${PGSQL_USER}"
echo "=========================================="
echo ""
echo "WARNING: This will permanently drop ALL tables (and dependent objects)"
echo "         in the 'public' schema of '${PGSQL_DATABASE}'. This cannot be undone."
echo ""
read -r -p "Type 'yes' to continue: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted. No changes made."
    exit 1
fi

echo ""
echo "---- Dropping all tables ----"

psql -h "${PGSQL_HOST}" -p "${PGSQL_PORT}" -U "${PGSQL_USER}" -d "${PGSQL_DATABASE}" -v ON_ERROR_STOP=1 <<'EOSQL'
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
    LOOP
        EXECUTE 'DROP TABLE IF EXISTS public.' || quote_ident(r.tablename) || ' CASCADE';
        RAISE NOTICE 'Dropped table: %', r.tablename;
    END LOOP;
END $$;
EOSQL

echo ""
echo "---- Verifying remaining tables in 'public' schema ----"
psql -h "${PGSQL_HOST}" -p "${PGSQL_PORT}" -U "${PGSQL_USER}" -d "${PGSQL_DATABASE}" -c "\dt public.*"

unset PGPASSWORD

echo ""
echo "Done."

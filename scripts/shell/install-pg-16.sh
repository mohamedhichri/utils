#!/bin/bash
set -e

PGSQL_VERSION=16
PGSQL_DATABASE=dssdesigndb
PGSQL_USER=dssruntimedbuser
# Password recommended to change
PGSQL_PWD=D@taikuP4ssF0rDB!

# New data directory location on /app
PGDATA_DIR=/app/pgsql/data

function lineinfile() { line=${2//\//\\/} ; sed -i -e '/'"${1//\//\\/}"'/{s/.*/'"${line}"'/;:a;n;ba;q};$a'"${line}" "$3" ; }

# This script is dedicated to postgresql installation
echo "---- Enable PostgreSQL module ----"
dnf -y install @postgresql:${PGSQL_VERSION}

echo "---- Install PostgreSQL packages ----"
dnf -y install postgresql-server python3-psycopg2 postgresql-jdbc

echo "---- Stop PostgreSQL service (in case it was previously initialized) ----"
systemctl stop postgresql

echo "---- Create data directory on /app ----"
mkdir -p "${PGDATA_DIR}"
chown -R postgres:postgres /app/pgsql
chmod 700 "${PGDATA_DIR}"

echo "---- Set SELinux context for new PGDATA path ----"
# Ensures postgres can write to /app under SELinux enforcing mode
semanage fcontext -a -t postgresql_db_t "${PGDATA_DIR}(/.*)?" 2>/dev/null || \
  semanage fcontext -m -t postgresql_db_t "${PGDATA_DIR}(/.*)?"
restorecon -R -v /app/pgsql

echo "---- Create systemd override to point PGDATA to /app ----"
mkdir -p /etc/systemd/system/postgresql.service.d
cat > /etc/systemd/system/postgresql.service.d/override.conf <<EOF
[Service]
Environment=PGDATA=${PGDATA_DIR}
EOF
systemctl daemon-reload

echo "---- Initialize PostgreSQL database in ${PGDATA_DIR} ----"
export PGDATA="${PGDATA_DIR}"
/usr/bin/postgresql-setup --initdb

echo "---- backup ${PGDATA_DIR}/pg_hba.conf ----"
cp "${PGDATA_DIR}/pg_hba.conf" "${PGDATA_DIR}/pg_hba.conf.bck"

echo "---- Replace ident authentication by md5 ----"
sed -i '/host/s/\<ident\>/md5/g' "${PGDATA_DIR}/pg_hba.conf"

echo "---- backup ${PGDATA_DIR}/postgresql.conf ----"
cp "${PGDATA_DIR}/postgresql.conf" "${PGDATA_DIR}/postgresql.conf.bck"

echo "---- Update max_connections ----"
lineinfile "^max_connections" "max_connections = 500" "${PGDATA_DIR}/postgresql.conf"

echo "---- Update shared_buffers ----"
lineinfile "^shared_buffers" "shared_buffers = 512MB" "${PGDATA_DIR}/postgresql.conf"

echo "---- Start PostgreSQL service ----"
systemctl enable postgresql
systemctl start postgresql

echo "---- Verify PostgreSQL is running on the new data directory ----"
su - postgres -c "psql -c \"SHOW data_directory\""
su - postgres -c "psql -c \"SHOW max_connections\""

echo "---- Create database:$PGSQL_DATABASE and user $PGSQL_USER ----"
su - postgres -c "psql -c \"CREATE DATABASE $PGSQL_DATABASE\""
su - postgres -c "psql -c \"CREATE USER $PGSQL_USER WITH ENCRYPTED PASSWORD '$PGSQL_PWD'\""
su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE $PGSQL_DATABASE TO $PGSQL_USER\""
su - postgres -c "psql -c \"ALTER DATABASE $PGSQL_DATABASE OWNER TO $PGSQL_USER\""

echo "---- Done. PostgreSQL ${PGSQL_VERSION} installed, data directory: ${PGDATA_DIR} ----"

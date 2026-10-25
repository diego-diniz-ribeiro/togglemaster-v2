#!/bin/sh
# Runs once, on the first start of an empty data volume (local), or as a
# one-shot Kubernetes Job against RDS (PGHOST/PGPASSWORD set; see the aws overlay).
# For each service listed in SERVICE_DATABASES (e.g. "auth flags") it creates:
#   - a login role  <svc>_user  with password from <SVC>_DB_PASSWORD
#   - a database    <svc>_db    owned by that role, closed to everyone else
# and applies /initdb/<svc>.sql as the service role, so it owns its tables.
set -eu

for svc in $SERVICE_DATABASES; do
  user="${svc}_user"
  db="${svc}_db"
  pw_var="$(echo "$svc" | tr '[:lower:]' '[:upper:]')_DB_PASSWORD"
  eval "pw=\${$pw_var:?$pw_var must be set}"

  echo "Creating database $db owned by $user"
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
       -v usr="$user" -v pw="$pw" -v db="$db" <<'SQL'
CREATE ROLE :"usr" LOGIN PASSWORD :'pw';
-- Managed PostgreSQL (RDS) has no superuser: the admin role must be a member
-- of the service role to create a database owned by it.
GRANT :"usr" TO CURRENT_USER;
CREATE DATABASE :"db" OWNER :"usr";
-- New databases accept connections from any role by default (PUBLIC).
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
SQL

  # Schema created by the service role itself, so it owns its tables. The
  # password is only checked on TCP connections (e.g. RDS via PGHOST).
  PGPASSWORD="$pw" psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" -f "/initdb/$svc.sql"
done

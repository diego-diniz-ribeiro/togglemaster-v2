#!/bin/sh
# Runs once, on the first start of an empty data volume.
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
CREATE DATABASE :"db" OWNER :"usr";
-- New databases accept connections from any role by default (PUBLIC).
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
SQL

  psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" -f "/initdb/$svc.sql"
done

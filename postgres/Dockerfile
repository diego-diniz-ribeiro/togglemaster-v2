# PostgreSQL image shared by both local instances, with init scripts baked in.
# Bind-mounting Windows paths fails on Podman ("incorrect volume format"),
# so the scripts are copied into the image instead.
# Build context is repos/fase-2 (parent folder) so each service's db/ is reachable.
# Each container chooses which databases to create via SERVICE_DATABASES.
FROM postgres:16-alpine

COPY togglemaster-v2/postgres/init-service-databases.sh /docker-entrypoint-initdb.d/init.sh
COPY auth-service/db/init.sql /initdb/auth.sql
COPY flag-service/db/init.sql /initdb/flags.sql
COPY targeting-service/db/init.sql /initdb/targeting.sql

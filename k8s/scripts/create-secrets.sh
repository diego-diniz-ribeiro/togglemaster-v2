#!/usr/bin/env bash
# Creates/updates the Kubernetes Secrets from an env file, so real values never
# go to Git.
#
# Usage:
#   k8s/scripts/create-secrets.sh local .env       # kind (in-cluster PostgreSQL)
#   k8s/scripts/create-secrets.sh aws   .env.aws   # EKS (RDS)
#
# Required variables: AUTH_DB_PASSWORD, FLAGS_DB_PASSWORD,
#   TARGETING_DB_PASSWORD, MASTER_KEY, POSTGRES_USER, POSTGRES_PASSWORD.
# aws mode also requires DB_HOST (RDS endpoint). Optional: DB_SSLMODE.
set -euo pipefail

MODE=${1:?usage: $0 <local|aws> <env-file>}
ENV_FILE=${2:?usage: $0 <local|aws> <env-file>}
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

: "${AUTH_DB_PASSWORD:?}" "${FLAGS_DB_PASSWORD:?}" "${TARGETING_DB_PASSWORD:?}"
: "${MASTER_KEY:?}" "${POSTGRES_USER:?}" "${POSTGRES_PASSWORD:?}"

APP_NS=togglemaster-app

# kubectl create ... --dry-run | kubectl apply  ==> create or update (idempotent).
apply_secret() {
  local name=$1 ns=$2
  shift 2
  local args=()
  for kv in "$@"; do args+=("--from-literal=$kv"); done
  kubectl create secret generic "$name" -n "$ns" "${args[@]}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

case "$MODE" in
  local)
    DATA_NS=togglemaster-data
    AUTH_FLAGS_HOST=postgres-auth-flags.$DATA_NS.svc.cluster.local
    TARGETING_HOST=postgres-targeting.$DATA_NS.svc.cluster.local
    SSLMODE=${DB_SSLMODE:-disable}
    apply_secret postgres-auth-flags "$DATA_NS" \
      "POSTGRES_USER=$POSTGRES_USER" "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
      "AUTH_DB_PASSWORD=$AUTH_DB_PASSWORD" "FLAGS_DB_PASSWORD=$FLAGS_DB_PASSWORD"
    apply_secret postgres-targeting "$DATA_NS" \
      "POSTGRES_USER=$POSTGRES_USER" "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
      "TARGETING_DB_PASSWORD=$TARGETING_DB_PASSWORD"
    ;;
  aws)
    : "${DB_HOST:?DB_HOST (RDS endpoint) is required in aws mode}"
    AUTH_FLAGS_HOST=$DB_HOST
    TARGETING_HOST=$DB_HOST
    SSLMODE=${DB_SSLMODE:-require}
    # Used by the db-init Job to create the roles/databases in RDS.
    apply_secret db-init "$APP_NS" \
      "PGHOST=$DB_HOST" "POSTGRES_USER=$POSTGRES_USER" "PGPASSWORD=$POSTGRES_PASSWORD" \
      "AUTH_DB_PASSWORD=$AUTH_DB_PASSWORD" "FLAGS_DB_PASSWORD=$FLAGS_DB_PASSWORD" \
      "TARGETING_DB_PASSWORD=$TARGETING_DB_PASSWORD"
    ;;
  *)
    echo "mode must be local or aws" >&2
    exit 1
    ;;
esac

apply_secret auth-service-secret "$APP_NS" \
  "DATABASE_URL=postgres://auth_user:$AUTH_DB_PASSWORD@$AUTH_FLAGS_HOST:5432/auth_db?sslmode=$SSLMODE" \
  "MASTER_KEY=$MASTER_KEY"
apply_secret flag-service-secret "$APP_NS" \
  "DATABASE_URL=postgres://flags_user:$FLAGS_DB_PASSWORD@$AUTH_FLAGS_HOST:5432/flags_db?sslmode=$SSLMODE"
apply_secret targeting-service-secret "$APP_NS" \
  "DATABASE_URL=postgres://targeting_user:$TARGETING_DB_PASSWORD@$TARGETING_HOST:5432/targeting_db?sslmode=$SSLMODE"

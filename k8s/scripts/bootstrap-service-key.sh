#!/usr/bin/env bash
# Bootstrap: evaluation-service needs an API key that only exists after
# auth-service is running. This script creates it through POST /admin/keys
# (authenticated with MASTER_KEY) and stores it in the evaluation Secret.
#
# Usage: k8s/scripts/bootstrap-service-key.sh <env-file>
set -euo pipefail

ENV_FILE=${1:?usage: $0 <env-file>}
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
: "${MASTER_KEY:?}"

NS=togglemaster-app
PORT=18001
# Never send localhost traffic through a corporate HTTP proxy.
CURL=(curl --noproxy "*")

kubectl rollout status deploy/auth-service -n "$NS" --timeout=180s

# Temporary tunnel to the ClusterIP Service (auth-service is not exposed directly).
kubectl port-forward -n "$NS" svc/auth-service "$PORT:8001" >/dev/null &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do
  "${CURL[@]}" -s -o /dev/null "http://localhost:$PORT/health" && break
  sleep 1
done

RESPONSE=$("${CURL[@]}" -fsS -X POST "http://localhost:$PORT/admin/keys" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name":"evaluation-service"}')
KEY=$(printf '%s' "$RESPONSE" | sed -n 's/.*"key":"\([^"]*\)".*/\1/p')
[ -n "$KEY" ] || { echo "could not read the key from: $RESPONSE" >&2; exit 1; }

kubectl create secret generic evaluation-service-secret -n "$NS" \
  --from-literal="SERVICE_API_KEY=$KEY" --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deploy/evaluation-service -n "$NS"
echo "SERVICE_API_KEY created (${KEY:0:10}...) and evaluation-service restarted"

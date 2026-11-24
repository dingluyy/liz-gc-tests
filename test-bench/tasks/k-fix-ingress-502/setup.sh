#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${ROOT_DIR}/artifacts/ingress-502-test.yaml"

NAMESPACE="ingress-fail-ns"
DEPLOYMENT="web-service"
SERVICE="web-service"
INGRESS="api-ingress"
HOST="api.test-502.com"

# Ingress Controller location (override via env if needed)
CTRL_NS="${CTRL_NS:-ingress-nginx}"
CTRL_SVC="${CTRL_SVC:-ingress-nginx-controller}"
LOCAL_PORT="${LOCAL_PORT:-18080}"

echo "[setup] Cleanup previous run..."
"${ROOT_DIR}/cleanup.sh" >/dev/null 2>&1 || true

echo "[setup] Applying manifest: ${MANIFEST}"
kubectl apply -f "${MANIFEST}"

echo "[setup] Waiting for Deployment '${DEPLOYMENT}' to be Ready..."
kubectl -n "${NAMESPACE}" wait deployment/"${DEPLOYMENT}" --for=condition=Available --timeout=120s

echo "[setup] Evidence: Service targetPort (should be 8080 - wrong)"
kubectl -n "${NAMESPACE}" get svc "${SERVICE}" -o wide
kubectl -n "${NAMESPACE}" describe svc "${SERVICE}" | sed -n '1,120p'

echo "[setup] Evidence: Endpoints should exist (pods are Ready)"
kubectl -n "${NAMESPACE}" get endpoints "${SERVICE}" -o wide || true

echo "[setup] Starting port-forward to ingress controller svc/${CTRL_SVC} in ns/${CTRL_NS} ..."
kubectl -n "${CTRL_NS}" port-forward "svc/${CTRL_SVC}" "${LOCAL_PORT}:80" >/tmp/ing502_pf.log 2>&1 &
PF_PID=$!

cleanup_pf() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup_pf EXIT

echo "[setup] Waiting for local port ${LOCAL_PORT}..."
for i in {1..30}; do
  if curl -sS -o /dev/null "http://127.0.0.1:${LOCAL_PORT}/" 2>/dev/null; then
    break
  fi
  sleep 1
done

echo "[setup] Verifying failure injection: Ingress should return 502 for Host ${HOST} ..."
HTTP_CODE="$(curl -sS -o /tmp/ing502_body.out -w "%{http_code}" -H "Host: ${HOST}" "http://127.0.0.1:${LOCAL_PORT}/" || true)"
echo "[setup] HTTP status: ${HTTP_CODE}"
echo "[setup] Response body (first lines):"
head -n 20 /tmp/ing502_body.out || true

if [[ "${HTTP_CODE}" != "502" ]]; then
  echo "[setup][ERROR] Expected HTTP 502 but got ${HTTP_CODE}. Failure injection may be ineffective or controller differs."
  echo "[setup][HINT] If using Traefik on k3s, run with: CTRL_NS=kube-system CTRL_SVC=traefik"
  exit 2
fi

echo "[setup] OK: Failure injected (Ingress returns 502)."


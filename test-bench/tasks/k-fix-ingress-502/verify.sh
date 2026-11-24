#!/usr/bin/env bash
set -euo pipefail

# =========================
# Task-specific parameters
# =========================
NAMESPACE="ingress-fail-ns"
DEPLOYMENT="web-service"
SERVICE="web-service"
HOST="api.test-502.com"
EXPECTED_REPLICAS=2
TIMEOUT="180s"

# Optional overrides:
#   CTRL_NS=... CTRL_SVC=... ./verify.sh
CTRL_NS="${CTRL_NS:-}"
CTRL_SVC="${CTRL_SVC:-}"
LOCAL_PORT="${LOCAL_PORT:-}"   # if empty, will auto-pick

TASK_NAME="fix-ingress-502"
echo "Starting verification for ${TASK_NAME}..."

# =========================
# Helpers
# =========================
log() { echo "[$(date +%H:%M:%S)] $*"; }

fail() {
  echo "❌ $*" >&2
  exit 1
}

pick_free_port() {
  # Try preferred ports first, then fall back to random range
  local candidates=(18080 18081 18082 28080 38080)
  for p in "${candidates[@]}"; do
    if ! lsof -nP -iTCP:"${p}" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "${p}"
      return 0
    fi
  done
  # random-ish port range
  for p in $(seq 20000 20100); do
    if ! lsof -nP -iTCP:"${p}" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "${p}"
      return 0
    fi
  done
  return 1
}

svc_exists() {
  local ns="$1" svc="$2"
  kubectl -n "${ns}" get svc "${svc}" >/dev/null 2>&1
}

detect_ingress_controller() {
  # If user provided override, trust it.
  if [[ -n "${CTRL_NS}" && -n "${CTRL_SVC}" ]]; then
    log "Using user-provided ingress controller: ${CTRL_NS}/${CTRL_SVC}"
    return 0
  fi

  # Common ingress controllers:
  # 1) Traefik (k3s default)
  if svc_exists "kube-system" "traefik"; then
    CTRL_NS="kube-system"
    CTRL_SVC="traefik"
    log "Detected Traefik ingress controller: ${CTRL_NS}/${CTRL_SVC}"
    return 0
  fi

  # 2) ingress-nginx variants (rke2 often uses ingress-nginx namespace)
  # rke2 addon commonly: ns=ingress-nginx, svc=ingress-nginx-controller
  if svc_exists "ingress-nginx" "ingress-nginx-controller"; then
    CTRL_NS="ingress-nginx"
    CTRL_SVC="ingress-nginx-controller"
    log "Detected NGINX ingress controller: ${CTRL_NS}/${CTRL_SVC}"
    return 0
  fi

  # other common names
  if svc_exists "ingress-nginx" "nginx-ingress-controller"; then
    CTRL_NS="ingress-nginx"
    CTRL_SVC="nginx-ingress-controller"
    log "Detected NGINX ingress controller: ${CTRL_NS}/${CTRL_SVC}"
    return 0
  fi

  # Some setups use namespace nginx-ingress
  if svc_exists "nginx-ingress" "ingress-nginx-controller"; then
    CTRL_NS="nginx-ingress"
    CTRL_SVC="ingress-nginx-controller"
    log "Detected NGINX ingress controller: ${CTRL_NS}/${CTRL_SVC}"
    return 0
  fi
  if svc_exists "nginx-ingress" "nginx-ingress-controller"; then
    CTRL_NS="nginx-ingress"
    CTRL_SVC="nginx-ingress-controller"
    log "Detected NGINX ingress controller: ${CTRL_NS}/${CTRL_SVC}"
    return 0
  fi

  # Some rke2 environments may use kube-system ingress-nginx-controller
  if svc_exists "kube-system" "ingress-nginx-controller"; then
    CTRL_NS="kube-system"
    CTRL_SVC="ingress-nginx-controller"
    log "Detected NGINX ingress controller: ${CTRL_NS}/${CTRL_SVC}"
    return 0
  fi

  echo "❌ Cannot auto-detect ingress controller service. Please set CTRL_NS and CTRL_SVC." >&2
  echo "ℹ Here are candidate services:" >&2
  kubectl get svc -A | egrep -i 'ingress|nginx|traefik' || true
  exit 2
}

start_port_forward() {
  local ns="$1" svc="$2" local_port="$3" remote_port="$4" log_file="$5"

  log "Starting port-forward: svc/${svc} (${ns}) ${local_port}:${remote_port}"
  # Ensure svc exists
  kubectl -n "${ns}" get svc "${svc}" >/dev/null

  # Start in background
  kubectl -n "${ns}" port-forward "svc/${svc}" "${local_port}:${remote_port}" >"${log_file}" 2>&1 &
  local pf_pid=$!

  # Give it a moment to fail fast if it will
  sleep 1
  if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
    echo "❌ port-forward process exited immediately. Log:" >&2
    cat "${log_file}" >&2 || true
    exit 2
  fi

  # Wait until local port responds (just TCP connect)
  for i in {1..30}; do
    if curl -sS -o /dev/null "http://127.0.0.1:${local_port}/" 2>/dev/null; then
      echo "${pf_pid}"
      return 0
    fi
    # Also check process still alive
    if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
      echo "❌ port-forward died while waiting. Log:" >&2
      cat "${log_file}" >&2 || true
      exit 2
    fi
    sleep 1
  done

  echo "❌ port-forward did not become ready. Log:" >&2
  cat "${log_file}" >&2 || true
  kill "${pf_pid}" >/dev/null 2>&1 || true
  exit 2
}

# =========================
# 1) Deployment Ready check
# =========================
log "Wait for Deployment to be Ready (${EXPECTED_REPLICAS}/${EXPECTED_REPLICAS})..."
kubectl -n "${NAMESPACE}" rollout status deployment/"${DEPLOYMENT}" --timeout="${TIMEOUT}"

READY="$(kubectl -n "${NAMESPACE}" get deploy "${DEPLOYMENT}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
if [[ "${READY}" != "${EXPECTED_REPLICAS}" ]]; then
  kubectl -n "${NAMESPACE}" describe deploy "${DEPLOYMENT}" || true
  fail "Deployment readyReplicas=${READY}, expected ${EXPECTED_REPLICAS}"
fi
log "✅ Deployment readyReplicas=${READY}"

# =========================
# 2) Service targetPort check
# =========================
log "Verify Service targetPort is corrected (expect 80 or named port)..."
TARGET_PORT="$(kubectl -n "${NAMESPACE}" get svc "${SERVICE}" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || true)"
if [[ -z "${TARGET_PORT}" ]]; then
  kubectl -n "${NAMESPACE}" describe svc "${SERVICE}" || true
  fail "Unable to read Service targetPort"
fi

# Allow "80" or a named port. For named port, we still require it maps to containerPort 80.
# We'll do a lightweight check: if named, ensure container ports include 80 and name matches.
if [[ "${TARGET_PORT}" == "80" ]]; then
  log "✅ Service targetPort is 80"
else
  log "ℹ Service targetPort is '${TARGET_PORT}' (named). Validating it maps to containerPort 80..."
  # Fetch container ports + names
  PORTS_JSON="$(kubectl -n "${NAMESPACE}" get deploy "${DEPLOYMENT}" -o jsonpath='{range .spec.template.spec.containers[*].ports[*]}{.name}:{.containerPort}{"\n"}{end}' 2>/dev/null || true)"
  echo "${PORTS_JSON}" | grep -qE ":80$" || fail "Deployment does not expose containerPort 80; cannot accept named targetPort '${TARGET_PORT}'"
  # If a name exists in ports, ensure it matches TARGET_PORT
  if echo "${PORTS_JSON}" | grep -qE "^${TARGET_PORT}:"; then
    log "✅ Named targetPort '${TARGET_PORT}' maps to containerPort 80"
  else
    log "⚠ Named targetPort '${TARGET_PORT}' not found among container port names. Proceeding, but this may be misconfigured."
  fi
fi

# =========================
# 3) Endpoints check
# =========================
log "Verify Service endpoints exist..."
EP_IPS="$(kubectl -n "${NAMESPACE}" get endpoints "${SERVICE}" -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || true)"
EP_COUNT="$(echo "${EP_IPS}" | wc -w | tr -d ' ')"
if [[ "${EP_COUNT}" -lt 1 ]]; then
  kubectl -n "${NAMESPACE}" describe endpoints "${SERVICE}" || true
  fail "No endpoints found for service '${SERVICE}'"
fi
log "✅ Endpoints count: ${EP_COUNT}"

# =========================
# 4) Real routing check via port-forward + Host header
# =========================
detect_ingress_controller

if [[ -z "${LOCAL_PORT}" ]]; then
  LOCAL_PORT="$(pick_free_port)" || fail "Could not find a free local port for port-forward"
fi
log "Using local port ${LOCAL_PORT}"

PF_LOG="/tmp/ing502_pf_verify.log"
PF_PID="$(start_port_forward "${CTRL_NS}" "${CTRL_SVC}" "${LOCAL_PORT}" 80 "${PF_LOG}")"

cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

log "Curl ingress through port-forward with Host header '${HOST}' (expect 200)..."
HTTP_CODE="$(curl -sS -o /tmp/ing502_verify_body.out -w "%{http_code}" -H "Host: ${HOST}" "http://127.0.0.1:${LOCAL_PORT}/" || true)"
log "HTTP status: ${HTTP_CODE}"

if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "❌ Expected 200 but got ${HTTP_CODE}. Debug info:" >&2
  echo "--- Response body (first 80 lines) ---" >&2
  head -n 80 /tmp/ing502_verify_body.out 2>/dev/null >&2 || true
  echo "--- port-forward log ---" >&2
  cat "${PF_LOG}" >&2 || true
  exit 1
fi

# Validate backend content
if ! grep -qi "Welcome to nginx" /tmp/ing502_verify_body.out; then
  echo "❌ Response does not look like nginx welcome page. Body:" >&2
  head -n 80 /tmp/ing502_verify_body.out >&2 || true
  exit 1
fi

log "✅ Ingress routes successfully (200 + nginx welcome page)."
log "Verification successful."
exit 0


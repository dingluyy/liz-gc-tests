#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="webapp-backend"
DEPLOYMENT="backend-api"
TIMEOUT_ROLLOUT="120s"   # 等待 deployment rollout 的 timeout
DETECT_RETRIES=60        # 检测次数（每次 sleep 2s -> 最多 ~120s）
SLEEP_SECONDS=2

# helper: print and run
run() { echo "+ $*"; "$@"; }

# 1) ensure clean namespace (wait for deletion if needed)
echo "Deleting namespace if exists: $NAMESPACE"
kubectl delete namespace "$NAMESPACE" --ignore-not-found

# wait up to 60s for namespace deletion to finish (avoid create failing due to Terminating)
echo "Waiting up to 60s for namespace to be fully removed (if it existed)..."
kubectl wait --for=delete namespace/"$NAMESPACE" --timeout=60s 2>/dev/null || true

# 2) create namespace
echo "Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" || true

# 3) apply the YAML (make sure artifacts/memory-hungry-app.yaml exists)
if [ ! -f "artifacts/memory-hungry-app.yaml" ]; then
  echo "ERROR: artifacts/memory-hungry-app.yaml not found in current directory."
  exit 2
fi

echo "Applying deployment YAML..."
kubectl apply -f artifacts/memory-hungry-app.yaml

# 4) wait for rollout (don't exit on timeout; we still want to detect OOM)
echo "Waiting for rollout status (timeout: $TIMEOUT_ROLLOUT)..."
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout="$TIMEOUT_ROLLOUT" || true

# 5) detect OOMKilled by checking pod containerStatuses
echo "Polling pods for OOMKilled state (up to $((DETECT_RETRIES * SLEEP_SECONDS))s)..."

for i in $(seq 1 $DETECT_RETRIES); do
  # get any reason string from either current state or lastState terminated.reason
  # Use jq if available, otherwise use kubectl jsonpath fallback
  if command -v jq >/dev/null 2>&1; then
    reasons=$(kubectl get pods -n "$NAMESPACE" -o json | jq -r '
      .items[]?.status.containerStatuses[]? |
      (
        (.state.terminated.reason // empty),
        (.lastState.terminated.reason // empty)
      ) | select(. != null and . != "")' 2>/dev/null || true)
  else
    # jsonpath fallback: collect both fields if present
    reasons=$(kubectl get pods -n "$NAMESPACE" -o jsonpath="{range .items[*]}{range .status.containerStatuses[*]}{.state.terminated.reason}{' '}{.lastState.terminated.reason}{'\n'}{end}{end}" 2>/dev/null || true)
  fi

  if printf '%s\n' "$reasons" | grep -q -w "OOMKilled"; then
    echo "✅ OOMKilled detected!"
    # Print pod status for diagnosis
    echo "Pods status (kubectl get pods -n $NAMESPACE):"
    kubectl get pods -n "$NAMESPACE" -o wide || true
    echo
    echo "Pod descriptions (showing terminated reason lines):"
    kubectl describe pod -n "$NAMESPACE" || true
    exit 0
  fi

  # also optionally check for container restartcounts or CrashLoopBackOff
  if kubectl get pods -n "$NAMESPACE" 2>/dev/null | grep -E "CrashLoopBackOff|Error"; then
    echo "Note: Found pods in CrashLoopBackOff / Error — may indicate OOM or other issues. Printing pods:"
    kubectl get pods -n "$NAMESPACE" || true
  fi

  sleep "$SLEEP_SECONDS"
done

echo "❌ Failed to detect OOMKilled within timeout."
exit 1

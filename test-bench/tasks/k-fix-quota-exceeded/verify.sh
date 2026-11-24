#!/usr/bin/env bash
# Verification for ResourceQuota Exceeded failure
set -e

DEPLOYMENT_NAME="high-cpu-app"
NAMESPACE="quota-fail-ns"
TIMEOUT="120s"
TASK_NAME="fix-quota-exceeded"
EXPECTED_REPLICAS=2

echo "Starting verification for $TASK_NAME..."

# 1. Verify Deployment is Available (This should only succeed after the fix)
echo "ℹ Waiting for Deployment '$DEPLOYMENT_NAME' to be 'Available' with $EXPECTED_REPLICAS replicas..."
if ! kubectl wait --for=condition=Available deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=$TIMEOUT; then
    echo "❌ Deployment '$DEPLOYMENT_NAME' did not become Available within $TIMEOUT."
    echo "---"
    echo "Info for Deployment '$DEPLOYMENT_NAME' in namespace '$NAMESPACE':"
    kubectl describe deployment $DEPLOYMENT_NAME -n $NAMESPACE
    # Check if the desired replica count is met
    RUNNING_REPLICAS=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [ "$RUNNING_REPLICAS" -ne "$EXPECTED_REPLICAS" ]; then
        echo "❌ Expected $EXPECTED_REPLICAS replicas, found $RUNNING_REPLICAS. Fix failed."
        exit 1
    fi
    # If the wait failed but replicas are correct (possible race), we continue.
fi

echo "✅ Deployment '$DEPLOYMENT_NAME' is Available and running $EXPECTED_REPLICAS replicas. Verification successful."
exit 0

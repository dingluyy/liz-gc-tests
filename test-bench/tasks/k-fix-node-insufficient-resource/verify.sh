#!/usr/bin/env bash
# Verification for Node Insufficient Resource failure
set -e

DEPLOYMENT_NAME="oversized-app"
NAMESPACE="pending-resource-ns"
TIMEOUT="120s"
TASK_NAME="fix-node-insufficient-resource"
EXPECTED_REPLICAS=1

echo "Starting verification for $TASK_NAME..."

# 1. Verify Deployment is Available (This should only succeed after the fix)
echo "ℹ Waiting for Deployment '$DEPLOYMENT_NAME' to be 'Available' with $EXPECTED_REPLICAS replicas..."
if ! kubectl wait --for=condition=Available deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=$TIMEOUT; then
    echo "❌ Deployment '$DEPLOYMENT_NAME' did not become Available within $TIMEOUT."
    echo "---"
    echo "Info for Pods in namespace '$NAMESPACE':"
    kubectl get pods -n $NAMESPACE
    # 检查 Pod 状态是否仍为 Pending
    if kubectl get pods -n $NAMESPACE -l app=oversized-app -o jsonpath='{.items[*].status.phase}' | grep -q "Pending"; then
         echo "❌ Pods are still stuck in Pending state."
    fi
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT_NAME' is Available and running. Verification successful for $TASK_NAME."
exit 0

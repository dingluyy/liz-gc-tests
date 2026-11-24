#!/usr/bin/env bash
# Verification for Container Permission Failure
set -e

DEPLOYMENT_NAME="restricted-app"
NAMESPACE="permission-fail-ns"
TIMEOUT="120s"
TASK_NAME="fix-container-permission"
# Define the error string to look for in the logs
ERROR_STRING="Permission denied"

echo "Starting verification for $TASK_NAME..."

# 1. Verify the Deployment becomes Available (ensures pod is at least running)
echo "ℹ Waiting for Deployment '$DEPLOYMENT_NAME' to be 'Available'..."
if ! kubectl wait --for=condition=Available deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=$TIMEOUT; then
    echo "❌ Deployment '$DEPLOYMENT_NAME' did not become Available within $TIMEOUT."
    echo "---"
    kubectl describe deployment $DEPLOYMENT_NAME -n $NAMESPACE
    # Check if pods are failing early (e.g., CrashLoop)
    if kubectl get pods -n $NAMESPACE -l app=restricted-app -o jsonpath='{.items[*].status.phase}' | grep -q -v "Running"; then
         echo "❌ Pods are not even reaching Running state."
         # Try to get logs from a potentially crashing pod
         POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=restricted-app -o jsonpath='{.items[0].metadata.name}' --ignore-not-found)
         if [ -n "$POD_NAME" ]; then
             echo "--- Logs from Pod $POD_NAME ---"
             kubectl logs --tail=50 $POD_NAME -n $NAMESPACE || echo "(Failed to get logs)"
             echo "--- End Logs ---"
         fi
    fi
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT_NAME' is Available. Now checking Pod logs for permission errors..."

# 2. Get the name of a running pod from the deployment
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=restricted-app -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | awk '{print $1}') # Get the first running pod

if [ -z "$POD_NAME" ]; then
    echo "❌ Could not find a running pod for Deployment '$DEPLOYMENT_NAME' to check logs."
    exit 1
fi

echo "ℹ Checking logs of Pod '$POD_NAME' for error string: '$ERROR_STRING'..."

# 3. Check logs for the specific permission error
# Use --tail=10 to get recent logs. Add a sleep to ensure the command has run.
sleep 5 # Give the container a moment to try writing
if kubectl logs --tail=10 $POD_NAME -n $NAMESPACE | grep -q "$ERROR_STRING"; then
    echo "❌ Error string '$ERROR_STRING' found in Pod logs. Permissions issue still exists."
    echo "--- Logs from Pod $POD_NAME ---"
    kubectl logs --tail=50 $POD_NAME -n $NAMESPACE
    echo "--- End Logs ---"
    exit 1
else
    echo "✅ Error string '$ERROR_STRING' not found in recent Pod logs."
    echo "✅ Permissions appear to be fixed. Verification successful."
    exit 0
fi
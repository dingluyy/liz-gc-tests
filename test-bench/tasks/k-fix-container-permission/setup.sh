#!/usr/bin/env bash
set -e

# Cleanup any previous runs first
./cleanup.sh

# Deploy the faulty deployment
kubectl apply -f artifacts/permission-fail-test.yaml

echo "Waiting for pod to fail startup due to permission error..."
sleep 5
echo "Pod should be CrashLoopBackOff or constantly restarting due to 'Permission denied' in logs."

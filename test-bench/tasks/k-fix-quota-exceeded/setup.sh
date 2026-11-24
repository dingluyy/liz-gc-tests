#!/usr/bin/env bash
set -e

# Cleanup any previous runs first
./cleanup.sh

# Apply all artifacts: Namespace, ResourceQuota, and Deployment
echo "Applying ResourceQuota and Deployment..."
# Note: The deployment is designed to fail creation due to the quota limit.
# kubectl apply will return an error, but the Deployment resource *itself* is created.
# The controller will then fail to create the Pods.
kubectl apply -f artifacts/quota-exceeded-test.yaml

echo "Waiting for Deployment controller to attempt Pod creation..."
# Give controller time to fail Pod creation and log the Forbidden error
sleep 5
echo "Deployment applied. Pod creation should now be failing due to ResourceQuota violation (Forbidden error in events)."

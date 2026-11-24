#!/usr/bin/env bash
set -e

# Cleanup previous runs
./cleanup.sh

# Deploy all resources
kubectl apply -f artifacts/localhost-bind-test.yaml

echo "Waiting for all pods to be running..."
kubectl wait --for=condition=Available deployment/faulty-server -n localhost-fail-ns --timeout=60s
kubectl wait --for=condition=Available deployment/client-app -n localhost-fail-ns --timeout=60s

echo "Pods are running. Client logs should now show 'Connection Refused' errors."

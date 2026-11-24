#!/usr/bin/env bash
set -euo pipefail

echo "[cleanup] Deleting namespace ingress-fail-ns ..."
kubectl delete ns ingress-fail-ns --ignore-not-found=true
echo "[cleanup] Done."


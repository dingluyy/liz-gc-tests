#!/usr/bin/env bash
# Cleanup: Delete the namespace
kubectl delete namespace permission-fail-ns --ignore-not-found=true

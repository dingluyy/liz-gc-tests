#!/usr/bin/env bash
# Cleanup: Delete the namespace
kubectl delete namespace quota-fail-ns --ignore-not-found=true

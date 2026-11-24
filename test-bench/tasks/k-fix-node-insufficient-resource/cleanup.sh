#!/usr/bin/env bash
# Cleanup: Delete the namespace
kubectl delete namespace pending-resource-ns --ignore-not-found=true

#!/usr/bin/env bash
# Cleanup: Delete the namespace
kubectl delete namespace localhost-fail-ns --ignore-not-found=true

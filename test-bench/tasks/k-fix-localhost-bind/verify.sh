#!/usr/bin/env bash
# Verification for Application Listen on Localhost Failure - FINAL FIX
set -e

SERVER_DEPLOYMENT="faulty-server"
SERVICE_NAME="faulty-svc"
NAMESPACE="localhost-fail-ns"
TIMEOUT="120s"
TASK_NAME="fix-localhost-bind"
SUCCESS_CODE="200"

echo "Starting verification for $TASK_NAME..."

# 1. Wait for SERVER deployment to be Ready
if ! kubectl wait --for=condition=Available deployment/$SERVER_DEPLOYMENT -n $NAMESPACE --timeout=$TIMEOUT; then
    echo "❌ Server Deployment did not become Available within $TIMEOUT. Fix failed."
    exit 1
fi
echo "✅ Server Deployment is Ready."

# 2. **核心验证：使用临时 Pod 测试连通性**
echo "ℹ Running temporary pod to test connectivity to $SERVICE_NAME..."

# 修正：使用 'kubectl run --attach' 并管道到 AWK，只提取纯数字状态码
# --attach 选项确保我们只获取容器的输出。
RAW_OUTPUT=$(
    kubectl run temp-tester-$RANDOM -n $NAMESPACE --image=curlimages/curl --restart=Never --attach --rm -- \
    curl -s -o /dev/null -w '%{http_code}' http://$SERVICE_NAME/
)
# 提取输出中所有数字序列，并只取第一个（即 HTTP 状态码）
TEST_RESULT=$(echo "$RAW_OUTPUT" | grep -oE '[0-9]+' | head -n 1)


if [ "$TEST_RESULT" == "$SUCCESS_CODE" ]; then
    echo "✅ Connectivity Test Succeeded (HTTP Status $TEST_RESULT). Verification successful."
    exit 0
else
    echo "❌ Connectivity Test Failed. Received status: $TEST_RESULT (Expected 200)."
    echo "--- Server Logs (Fix Verification Failure) ---"
    SERVER_POD=$(kubectl get pod -l app=faulty-server -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
    kubectl logs $SERVER_POD -n $NAMESPACE --tail=5 || true

    exit 1
fi
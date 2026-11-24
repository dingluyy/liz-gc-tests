
#!/usr/bin/env bash
set -e

# 切换到当前脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Cleanup any previous runs first
./cleanup.sh

# Dynamically calculate CPU requests:
# Maximum allocatable CPU among Ready, schedulable nodes + 1 core
CPU_REQUEST=$(kubectl get nodes -o json | python3 -c '
import json
import sys
from decimal import Decimal, ROUND_CEILING

data = json.load(sys.stdin)
cpus = []

for node in data["items"]:
    if node.get("spec", {}).get("unschedulable", False):
        continue

    ready = any(
        c["type"] == "Ready" and c["status"] == "True"
        for c in node.get("status", {}).get("conditions", [])
    )

    if not ready:
        continue

    cpu = node["status"]["allocatable"]["cpu"]

    if cpu.endswith("m"):
        milli = Decimal(cpu[:-1])
    elif cpu.endswith("u"):
        milli = Decimal(cpu[:-1]) / 1000
    elif cpu.endswith("n"):
        milli = Decimal(cpu[:-1]) / 1000000
    else:
        milli = Decimal(cpu) * 1000

    cpus.append(milli)

if not cpus:
    sys.exit("ERROR: No Ready schedulable nodes found")

max_cpu = max(cpus).to_integral_value(rounding=ROUND_CEILING)
print(f"{int(max_cpu + 1000)}m")
')

echo "Maximum allocatable CPU: calculated"
echo "Pod CPU request: ${CPU_REQUEST}"

# Generate YAML with dynamically calculated CPU requests
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT

sed "s/__CPU_REQUEST__/${CPU_REQUEST}/g" \
    artifacts/insufficient-resource-test.yaml > "$TEMP_FILE"

# Create the namespace and deployment
kubectl apply -f "$TEMP_FILE"

echo "Waiting for Deployment to attempt Pod creation..."
# 等待调度器尝试调度并失败
sleep 10

echo "Pods should now be stuck in Pending with Insufficient CPU error."


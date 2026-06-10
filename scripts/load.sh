#!/usr/bin/env bash
# Generate sustained traffic against the inference service so GPU
# utilization (simulated or real) climbs and KEDA scales the deployment.
set -euo pipefail

CONTEXT="kind-gpu-lab"
DURATION="${1:-120}"

echo "Port-forwarding inference service..."
kubectl --context "$CONTEXT" -n inference port-forward svc/vllm 8000:8000 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 3

echo "Sending traffic for ${DURATION}s — watch: kubectl -n inference get hpa -w"
END=$((SECONDS + DURATION))
while [ $SECONDS -lt $END ]; do
  for _ in $(seq 1 20); do
    curl -s -o /dev/null -X POST http://localhost:8000/v1/completions \
      -H 'Content-Type: application/json' \
      -d '{"model":"llama-3-8b","prompt":"Explain GPU time-slicing","max_tokens":64}' &
  done
  wait
done
echo "Done."

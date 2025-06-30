# Operational Runbook

## 📋 Table of Contents
1. [Health Checks](#health-checks)
2. [Safe OP-Geth Restart](#safe-op-geth-restart)
3. [OP-Node Dry-Run Mode](#op-node-dry-run-mode)
4. [Troubleshooting /healthz = 206](#troubleshooting-healthz-206)

---

## 🏥 Health Checks

### Quick Health Assessment
```bash
# 1. Check all pods are running
kubectl get pods -n rollup -o wide
kubectl get pods -n ethereum -o wide

# 2. Verify services have endpoints
kubectl get endpoints -n rollup
kubectl get endpoints -n ethereum

# 3. Check recent events for issues
kubectl get events -n rollup --sort-by='.lastTimestamp' | head -20
```

### Component-Specific Health Checks

#### OP-Geth Health
```bash
# Check RPC availability
POD_NAME=$(kubectl get pod -n rollup -l app=op-geth -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n rollup $POD_NAME -- geth attach --exec "eth.syncing"

# Check peer connectivity
kubectl exec -n rollup $POD_NAME -- geth attach --exec "admin.peers.length"

# Check block height
kubectl exec -n rollup $POD_NAME -- geth attach --exec "eth.blockNumber"

# Check transaction pool
kubectl exec -n rollup $POD_NAME -- geth attach --exec "txpool.status"
```

#### OP-Node Health
```bash
# Check sync status
POD_NAME=$(kubectl get pod -n rollup -l app=op-node -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n rollup $POD_NAME -- curl -s http://localhost:9545/healthz

# Check L1/L2 connectivity
kubectl logs -n rollup $POD_NAME --tail=50 | grep -E "(L1|L2)" 

# Check sequencer status
kubectl exec -n rollup $POD_NAME -- curl -s http://localhost:7300/metrics | grep sequencer
```

### Monitoring Dashboard Checks
```bash
# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Key metrics to verify:
# - Block production rate > 0
# - Peer count > 5
# - No persistent errors in logs
# - CPU/Memory within limits
```

---

## 🔄 Safe OP-Geth Restart

### Pre-Restart Checklist
```bash
# 1. Check current sync status
POD_NAME=$(kubectl get pod -n rollup -l app=op-geth -o jsonpath="{.items[0].metadata.name}")
CURRENT_BLOCK=$(kubectl exec -n rollup $POD_NAME -- geth attach --exec "eth.blockNumber")
echo "Current block: $CURRENT_BLOCK"

# 2. Check if this is the only running instance
REPLICA_COUNT=$(kubectl get statefulset -n rollup op-geth -o jsonpath="{.spec.replicas}")
READY_COUNT=$(kubectl get statefulset -n rollup op-geth -o jsonpath="{.status.readyReplicas}")
echo "Replicas: $REPLICA_COUNT, Ready: $READY_COUNT"

# 3. Verify backup pod if in HA mode
if [ $REPLICA_COUNT -gt 1 ]; then
  echo "HA mode detected. Safe to proceed."
else
  echo "⚠️  Single instance mode. Expect downtime."
fi
```

### Restart Procedure

#### Method 1: Rolling Restart (Preferred)
```bash
# This ensures zero downtime if replicas > 1
kubectl rollout restart statefulset/op-geth -n rollup

# Monitor the rollout
kubectl rollout status statefulset/op-geth -n rollup --watch

# Verify pods are back
kubectl get pods -n rollup -l app=op-geth -w
```

#### Method 2: Controlled Pod Deletion
```bash
# For single pod restart
POD_NAME=$(kubectl get pod -n rollup -l app=op-geth -o jsonpath="{.items[0].metadata.name}")

# Gracefully terminate
kubectl delete pod $POD_NAME -n rollup --grace-period=30

# Watch new pod creation
kubectl get pods -n rollup -l app=op-geth -w

# Wait for readiness
kubectl wait --for=condition=ready pod -l app=op-geth -n rollup --timeout=300s
```

### Post-Restart Verification
```bash
# 1. Check new pod is syncing
NEW_POD=$(kubectl get pod -n rollup -l app=op-geth -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n rollup $NEW_POD -- geth attach --exec "eth.syncing"

# 2. Compare block height
NEW_BLOCK=$(kubectl exec -n rollup $NEW_POD -- geth attach --exec "eth.blockNumber")
echo "Previous block: $CURRENT_BLOCK, New block: $NEW_BLOCK"

# 3. Verify RPC endpoint
kubectl exec -n rollup $NEW_POD -- curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# 4. Check logs for errors
kubectl logs -n rollup $NEW_POD --tail=100 | grep -i error
```

---

## 🔄 OP-Node Dry-Run Mode

### Enable Dry-Run Mode via Debug API

#### Step 1: Access OP-Node Pod
```bash
# Get pod name
POD_NAME=$(kubectl get pod -n rollup -l app=op-node -o jsonpath="{.items[0].metadata.name}")

# Port forward debug API
kubectl port-forward -n rollup $POD_NAME 7300:7300 &
PF_PID=$!
```

#### Step 2: Enable Dry-Run Mode
```bash
# Set sequencer to dry-run mode
curl -X POST http://localhost:7300/debug/sequencer/dry-run \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}'

# Verify the change
curl http://localhost:7300/debug/sequencer/status | jq '.dry_run'
```

#### Step 3: Monitor Dry-Run Behavior
```bash
# Check that no batches are being submitted
kubectl logs -n rollup $POD_NAME -f | grep -E "(batch|dry-run)"

# Verify L1 interactions have stopped
kubectl logs -n rollup $POD_NAME --tail=100 | grep "L1.*submit"
```

### Disable Dry-Run Mode
```bash
# Disable dry-run
curl -X POST http://localhost:7300/debug/sequencer/dry-run \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}'

# Verify normal operation resumed
curl http://localhost:7300/debug/sequencer/status | jq '.dry_run'

# Clean up port forward
kill $PF_PID
```

### Verification Steps
```bash
# 1. Check batch submission resumed
kubectl logs -n rollup $POD_NAME --tail=50 | grep "batch.*submitted"

# 2. Monitor metrics
curl -s http://localhost:7300/metrics | grep -E "(batch|sequencer)"

# 3. Check health endpoint
curl http://localhost:9545/healthz
```

---

## 🔍 Troubleshooting /healthz = 206

### Understanding HTTP 206 (Partial Content)

HTTP 206 indicates the node is partially healthy - typically meaning it's syncing but not fully caught up.

### Diagnostic Steps

#### Step 1: Check Sync Status
```bash
# For OP-Node
POD_NAME=$(kubectl get pod -n rollup -l app=op-node -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n rollup $POD_NAME -- curl -s http://localhost:9545/healthz -v

# Check detailed sync status
kubectl exec -n rollup $POD_NAME -- curl -s http://localhost:7300/metrics | grep -E "(head|safe|finalized)"
```

#### Step 2: Identify Sync Gaps
```bash
# Check L1 head
L1_HEAD=$(kubectl logs -n rollup $POD_NAME --tail=100 | grep "L1 head" | tail -1)
echo "L1 Head: $L1_HEAD"

# Check L2 head
L2_HEAD=$(kubectl logs -n rollup $POD_NAME --tail=100 | grep "L2 head" | tail -1)
echo "L2 Head: $L2_HEAD"

# Calculate lag
kubectl exec -n rollup $POD_NAME -- curl -s http://localhost:7300/metrics | grep lag
```

#### Step 3: Common Causes & Fixes

**Cause 1: L1 Node Behind**
```bash
# Check L1 sync status
L1_POD=$(kubectl get pod -n ethereum -l app=execution-client -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n ethereum $L1_POD -- geth attach --exec "eth.syncing"

# Fix: Wait for L1 to catch up or use external L1 RPC
```

**Cause 2: Insufficient Peers**
```bash
# Check peer count
kubectl exec -n rollup $POD_NAME -- curl -s http://localhost:7300/metrics | grep peer_count

# Fix: Check network connectivity
kubectl describe pod -n rollup $POD_NAME | grep -A5 "Events:"
```

**Cause 3: Resource Constraints**
```bash
# Check resource usage
kubectl top pod -n rollup $POD_NAME

# Fix: Increase resource limits if needed
kubectl edit statefulset -n rollup op-node
```

### Resolution Workflow
```bash
# 1. Restart with increased verbosity
kubectl set env statefulset/op-node -n rollup OP_NODE_LOG_LEVEL=debug

# 2. Monitor sync progress
watch -n 5 'kubectl exec -n rollup $POD_NAME -- curl -s http://localhost:7300/metrics | grep -E "(head|lag)"'

# 3. Once caught up, verify health
kubectl exec -n rollup $POD_NAME -- curl -s http://localhost:9545/healthz

# 4. Reset log level
kubectl set env statefulset/op-node -n rollup OP_NODE_LOG_LEVEL=info
```

### Monitoring Sync Progress
```bash
# Create a sync monitoring loop
while true; do
  HEALTH=$(kubectl exec -n rollup $POD_NAME -- curl -s -o /dev/null -w "%{http_code}" http://localhost:9545/healthz)
  SAFE_BLOCK=$(kubectl exec -n rollup $POD_NAME -- curl -s http://localhost:7300/metrics | grep safe_head | awk '{print $2}')
  echo "$(date): Health=$HEALTH, Safe Block=$SAFE_BLOCK"
  
  if [ "$HEALTH" = "200" ]; then
    echo "✅ Node is fully synced!"
    break
  fi
  
  sleep 30
done
```

---

## 🚨 Emergency Procedures

### Complete Service Restart
```bash
# Stop all rollup components
kubectl scale statefulset op-geth op-node -n rollup --replicas=0

# Clear any stuck volumes (⚠️ only if necessary)
kubectl delete pvc -n rollup --all

# Restart components in order
kubectl scale statefulset op-geth -n rollup --replicas=1
kubectl wait --for=condition=ready pod -l app=op-geth -n rollup --timeout=300s

kubectl scale statefulset op-node -n rollup --replicas=1
kubectl wait --for=condition=ready pod -l app=op-node -n rollup --timeout=300s
```

### Fallback to External RPC
```bash
# Update ConfigMap with external RPC
kubectl edit configmap op-node-config -n rollup
# Change L1_RPC_ENDPOINT to external provider

# Restart op-node to pick up changes
kubectl rollout restart statefulset/op-node -n rollup
``` 
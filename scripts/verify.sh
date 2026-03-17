#!/bin/bash
set -e
export AWS_PAGER=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

AWS_REGION=${AWS_REGION:-eu-west-1}
CLUSTER_NAME=${CLUSTER_NAME:-eks-cluster}
AWS_PROFILE_NAME=${AWS_PROFILE_NAME:-${CLUSTER_NAME}}

if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile "$AWS_PROFILE_NAME"
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile "$AWS_PROFILE_NAME"
    aws configure set region "$AWS_REGION" --profile "$AWS_PROFILE_NAME"
    export AWS_PROFILE="$AWS_PROFILE_NAME"
elif aws configure list --profile "$AWS_PROFILE_NAME" &>/dev/null; then
    export AWS_PROFILE="$AWS_PROFILE_NAME"
fi

PASS=0
FAIL=0
WARN=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN + 1)); }

echo "=========================================="
echo " EKS Cluster Verification"
echo "=========================================="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Region:  $AWS_REGION"
echo ""

echo "--- 1. EKS Cluster Status ---"
CLUSTER_STATUS=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "cluster.status" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
  pass "Cluster is ACTIVE"
else
  fail "Cluster status: $CLUSTER_STATUS"
fi

CLUSTER_VERSION=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "cluster.version" \
  --output text 2>/dev/null || echo "unknown")
echo "  Kubernetes version: $CLUSTER_VERSION"
echo ""

echo "--- 2. Node Health ---"
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")

if [ "$NODE_COUNT" -gt 0 ] && [ "$NODE_COUNT" = "$READY_COUNT" ]; then
  pass "All $NODE_COUNT nodes are Ready"
elif [ "$NODE_COUNT" -gt 0 ]; then
  fail "$READY_COUNT/$NODE_COUNT nodes are Ready"
else
  fail "No nodes found"
fi
kubectl get nodes -o wide 2>/dev/null || true
echo ""

echo "--- 3. System Pods ---"
POD_OUTPUT=$(kubectl get pods -A --no-headers 2>/dev/null || true)
TOTAL_PODS=$(echo "$POD_OUTPUT" | grep -c . || true)
RUNNING_PODS=$(echo "$POD_OUTPUT" | grep -cE "Running|Completed" || true)
FAILED_PODS=$(echo "$POD_OUTPUT" | grep -cE "Error|CrashLoopBackOff|ImagePullBackOff" || true)

if [ "$FAILED_PODS" -eq 0 ] && [ "$TOTAL_PODS" -gt 0 ]; then
  pass "All $TOTAL_PODS pods healthy ($RUNNING_PODS running)"
elif [ "$FAILED_PODS" -gt 0 ]; then
  fail "$FAILED_PODS pods in error state out of $TOTAL_PODS total"
  echo "$POD_OUTPUT" | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" || true
else
  fail "No pods found"
fi
echo ""

echo "--- 4. EKS Add-ons ---"
ADDONS=$(aws eks list-addons \
  --cluster-name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "addons" \
  --output text 2>/dev/null || echo "")

for addon in coredns kube-proxy vpc-cni aws-ebs-csi-driver amazon-cloudwatch-observability; do
  if echo "$ADDONS" | grep -q "$addon"; then
    ADDON_STATUS=$(aws eks describe-addon \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name "$addon" \
      --region "$AWS_REGION" \
      --query "addon.status" \
      --output text 2>/dev/null || echo "UNKNOWN")
    if [ "$ADDON_STATUS" = "ACTIVE" ]; then
      pass "Add-on $addon is ACTIVE"
    else
      warn "Add-on $addon status: $ADDON_STATUS"
    fi
  else
    if [ "$addon" = "amazon-cloudwatch-observability" ]; then
      warn "Add-on $addon not installed (enable_cloudwatch_observability may be false)"
    else
      fail "Add-on $addon not found"
    fi
  fi
done
echo ""

echo "--- 5. Helm Releases ---"
for release_ns in "aws-load-balancer-controller:kube-system" "cluster-autoscaler:kube-system" "prometheus:monitoring"; do
  release=$(echo "$release_ns" | cut -d: -f1)
  ns=$(echo "$release_ns" | cut -d: -f2)
  if helm status "$release" -n "$ns" &>/dev/null; then
    pass "Helm release $release deployed in $ns"
  else
    warn "Helm release $release not found in $ns"
  fi
done
echo ""

echo "--- 6. EKS Control Plane Logs (CloudWatch) ---"
CP_LOG_GROUP="/aws/eks/$CLUSTER_NAME/cluster"
CP_LOG_EXISTS=$(aws logs describe-log-groups \
  --log-group-name-prefix "$CP_LOG_GROUP" \
  --region "$AWS_REGION" \
  --query "logGroups[?logGroupName=='$CP_LOG_GROUP'].logGroupName" \
  --output text 2>/dev/null || echo "")

if [ -n "$CP_LOG_EXISTS" ]; then
  pass "Control plane log group exists: $CP_LOG_GROUP"

  CP_STREAMS=$(aws logs describe-log-streams \
    --log-group-name "$CP_LOG_GROUP" \
    --region "$AWS_REGION" \
    --order-by LastEventTime \
    --descending \
    --max-items 5 \
    --query "logStreams[].logStreamName" \
    --output text 2>/dev/null || echo "")

  if [ -n "$CP_STREAMS" ]; then
    pass "Control plane log streams are being written"
  else
    warn "No log streams found yet in control plane log group"
  fi
else
  fail "Control plane log group not found: $CP_LOG_GROUP"
fi
echo ""

echo "--- 7. Container Logs (CloudWatch) ---"
CONTAINER_LOG_GROUPS=$(aws logs describe-log-groups \
  --log-group-name-prefix "/aws/containerinsights/$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "logGroups[].logGroupName" \
  --output text 2>/dev/null || echo "")

if [ -n "$CONTAINER_LOG_GROUPS" ]; then
  pass "Container Insights log groups found"
  for lg in $CONTAINER_LOG_GROUPS; do
    STREAM_COUNT=$(aws logs describe-log-streams \
      --log-group-name "$lg" \
      --region "$AWS_REGION" \
      --query "length(logStreams)" \
      --output text 2>/dev/null | head -1 || echo "0")
    if [ "$STREAM_COUNT" -gt 0 ] 2>/dev/null; then
      pass "Log group $lg has log streams"
    else
      warn "Log group $lg has no streams yet"
    fi
  done
else
  FLUENT_LOG_GROUP="/aws/eks/$CLUSTER_NAME/containers"
  FLUENT_EXISTS=$(aws logs describe-log-groups \
    --log-group-name-prefix "$FLUENT_LOG_GROUP" \
    --region "$AWS_REGION" \
    --query "logGroups[?logGroupName=='$FLUENT_LOG_GROUP'].logGroupName" \
    --output text 2>/dev/null || echo "")

  if [ -n "$FLUENT_EXISTS" ]; then
    pass "Container log group exists: $FLUENT_LOG_GROUP"
  else
    warn "No container log groups found yet (CloudWatch agent may still be initializing)"
  fi
fi
echo ""

echo "--- 8. Container Insights Metrics (CloudWatch) ---"
METRICS=$(aws cloudwatch list-metrics \
  --namespace "ContainerInsights" \
  --region "$AWS_REGION" \
  --dimensions "Name=ClusterName,Value=$CLUSTER_NAME" \
  --output json 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('Metrics',[])))" 2>/dev/null || echo "0")

if [ "$METRICS" -gt 0 ] 2>/dev/null; then
  pass "Container Insights metrics found ($METRICS metric(s) for cluster)"
else
  warn "No Container Insights metrics yet (agent may need a few minutes to start reporting)"
fi
echo ""

echo "=========================================="
echo " Verification Summary"
echo "=========================================="
echo ""
echo "  Passed:   $PASS"
echo "  Failed:   $FAIL"
echo "  Warnings: $WARN"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "❌ Verification FAILED - $FAIL check(s) did not pass"
  exit 1
else
  echo "✅ Verification PASSED"
  exit 0
fi

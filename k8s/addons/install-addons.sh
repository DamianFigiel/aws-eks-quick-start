#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get command-line arguments
CLUSTER_NAME=${1:-${CLUSTER_NAME}}
AWS_REGION=${2:-${AWS_REGION:-eu-west-1}}
AWS_LB_CONTROLLER_ROLE_ARN=${3:-${AWS_LB_CONTROLLER_ROLE_ARN}}
CLUSTER_AUTOSCALER_ROLE_ARN=${4:-${CLUSTER_AUTOSCALER_ROLE_ARN}}

if [ -z "$CLUSTER_NAME" ]; then
  echo "❌ No cluster name provided. Usage: $0 <cluster-name> [aws-region]"
  exit 1
fi

echo "🔍 Getting cluster information..."
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.resourcesVpcConfig.vpcId" --output text)

echo "🔍 Using IAM role ARNs from Terraform..."
# Use the environment variables exported from deploy.sh
# If they're not set, provide a helpful error message
if [ -z "$AWS_LB_CONTROLLER_ROLE_ARN" ]; then
  echo "❌ AWS_LB_CONTROLLER_ROLE_ARN environment variable not set. Make sure terraform was applied successfully."
  exit 1
fi

if [ -z "$CLUSTER_AUTOSCALER_ROLE_ARN" ]; then
  echo "❌ CLUSTER_AUTOSCALER_ROLE_ARN environment variable not set. Make sure terraform was applied successfully."
  exit 1
fi

echo "📦 AWS Load Balancer Controller Role ARN: $AWS_LB_CONTROLLER_ROLE_ARN"
echo "📦 Cluster Autoscaler Role ARN: $CLUSTER_AUTOSCALER_ROLE_ARN"

echo "📦 Installing AWS Load Balancer Controller..."
# Replace variables in the values file
sed -e "s|\${CLUSTER_NAME}|$CLUSTER_NAME|g" \
    -e "s|\${AWS_REGION}|$AWS_REGION|g" \
    -e "s|\${VPC_ID}|$VPC_ID|g" \
    -e "s|\${AWS_LB_CONTROLLER_ROLE_ARN}|$AWS_LB_CONTROLLER_ROLE_ARN|g" \
    "$SCRIPT_DIR/aws-load-balancer-controller-values.yaml" > /tmp/aws-lb-values.yaml

# Add Helm repo and install chart
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  -f /tmp/aws-lb-values.yaml

echo "⏳ Waiting for AWS Load Balancer Controller to be ready..."
kubectl -n kube-system wait --for=condition=available deployment/aws-load-balancer-controller --timeout=120s

echo "📦 Installing Cluster Autoscaler..."
# Replace variables in the values file
sed -e "s|\${CLUSTER_NAME}|$CLUSTER_NAME|g" \
    -e "s|\${AWS_REGION}|$AWS_REGION|g" \
    -e "s|\${CLUSTER_AUTOSCALER_ROLE_ARN}|$CLUSTER_AUTOSCALER_ROLE_ARN|g" \
    "$SCRIPT_DIR/cluster-autoscaler-values.yaml" > /tmp/cluster-autoscaler-values.yaml

# Add Helm repo and install chart
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  -f /tmp/cluster-autoscaler-values.yaml

echo "📦 Installing Prometheus Stack..."
# First create the namespace if it doesn't exist
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Replace variables in the values file if needed
cp "$SCRIPT_DIR/prometheus-values.yaml" /tmp/prometheus-values.yaml

# Add Helm repo and install chart
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f /tmp/prometheus-values.yaml \
  --timeout 10m

echo "✅ Add-ons installation completed!" 
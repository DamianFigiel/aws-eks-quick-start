#!/bin/bash
set -e

echo "🚀 Starting Phylax Rollup Infrastructure Deployment"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

AWS_REGION=${AWS_REGION:-us-west-2}
CLUSTER_NAME=${CLUSTER_NAME:-phylax-rollup}

check_dependencies() {
    echo "🔍 Checking dependencies..."
    
    if ! command -v terraform &> /dev/null; then
        echo "❌ Terraform is not installed. Please install Terraform."
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl is not installed. Please install kubectl."
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI is not installed. Please install AWS CLI."
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        echo "❌ Helm is not installed. Please install Helm."
        exit 1
    fi
    
    echo "✅ All dependencies are available"
}

check_aws_credentials() {
    echo "🔍 Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    echo "✅ AWS credentials are configured"
}

deploy_terraform() {
    echo "🏗️ Deploying Terraform infrastructure..."
    
    cd "$PROJECT_ROOT/terraform"
    
    echo "🔧 Initializing Terraform..."
    terraform init
    
    echo "📋 Planning Terraform deployment..."
    terraform plan -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME"
    
    echo "🚀 Applying Terraform configuration..."
    terraform apply -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME" -auto-approve
    
    echo "📝 Getting outputs..."
    CLUSTER_NAME_FULL=$(terraform output -raw cluster_name)
    VPC_ID=$(terraform output -raw vpc_id)
    
    echo "✅ Terraform deployment completed"
    echo "📊 Cluster Name: $CLUSTER_NAME_FULL"
    echo "📊 VPC ID: $VPC_ID"
    
    cd "$PROJECT_ROOT"
}

configure_kubectl() {
    echo "⚙️ Configuring kubectl..."
    
    cd "$PROJECT_ROOT/terraform"
    CLUSTER_NAME_FULL=$(terraform output -raw cluster_name)
    cd "$PROJECT_ROOT"
    
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME_FULL"
    
    echo "🔍 Testing cluster connection..."
    kubectl get nodes
    
    echo "✅ kubectl configured successfully"
}

deploy_kubernetes() {
    echo "☸️ Deploying Kubernetes resources..."
    
    echo "📦 Creating namespaces..."
    kubectl apply -f "$PROJECT_ROOT/k8s/namespaces.yaml"
    
    echo "📦 Creating ConfigMaps and Secrets..."
    kubectl apply -f "$PROJECT_ROOT/k8s/configmaps.yaml"
    
    echo "📦 Creating Persistent Volume Claims..."
    kubectl apply -f "$PROJECT_ROOT/k8s/persistent-volumes.yaml"
    
    echo "📦 Deploying Ethereum infrastructure..."
    kubectl apply -f "$PROJECT_ROOT/k8s/ethereum-execution.yaml"
    kubectl apply -f "$PROJECT_ROOT/k8s/ethereum-beacon.yaml"
    
    echo "⏳ Waiting for Ethereum nodes to be ready..."
    kubectl wait --for=condition=ready pod -l app=execution-client -n ethereum --timeout=600s
    
    echo "📦 Deploying Rollup infrastructure..."
    kubectl apply -f "$PROJECT_ROOT/k8s/op-geth.yaml"
    kubectl apply -f "$PROJECT_ROOT/k8s/op-node.yaml"
    
    echo "📦 Deploying monitoring..."
    kubectl apply -f "$PROJECT_ROOT/k8s/monitoring.yaml"
    
    echo "✅ Kubernetes resources deployed successfully"
}

wait_for_services() {
    echo "⏳ Waiting for services to be ready..."
    
    echo "⏳ Waiting for OP-Geth..."
    kubectl wait --for=condition=ready pod -l app=op-geth -n rollup --timeout=600s
    
    echo "⏳ Waiting for OP-Node..."
    kubectl wait --for=condition=ready pod -l app=op-node -n rollup --timeout=600s
    
    echo "✅ All services are ready"
}

get_service_info() {
    echo "📊 Getting service information..."
    
    echo "🔗 LoadBalancer Services:"
    kubectl get svc -n rollup op-geth-external
    
    echo "🔗 Internal Services:"
    kubectl get svc -n rollup
    kubectl get svc -n ethereum
    
    echo "📊 Pod Status:"
    kubectl get pods -n rollup
    kubectl get pods -n ethereum
    
    if kubectl get svc -n monitoring prometheus-grafana &> /dev/null; then
        echo "📊 Monitoring:"
        kubectl get svc -n monitoring
        echo "📊 Grafana admin password: admin"
    fi
}

main() {
    check_dependencies
    check_aws_credentials
    deploy_terraform
    configure_kubectl
    deploy_kubernetes
    wait_for_services
    get_service_info
    
    echo ""
    echo "🎉 Phylax Rollup Infrastructure deployment completed successfully!"
    echo ""
    echo "📋 Next steps:"
    echo "1. Access your rollup RPC at the LoadBalancer endpoint"
    echo "2. Monitor your infrastructure using Grafana"
    echo "3. Check logs with: kubectl logs -f <pod-name> -n <namespace>"
    echo ""
    echo "🔧 Useful commands:"
    echo "kubectl get pods -n rollup"
    echo "kubectl get pods -n ethereum"
    echo "kubectl logs -f deployment/op-geth -n rollup"
    echo "kubectl logs -f deployment/op-node -n rollup"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
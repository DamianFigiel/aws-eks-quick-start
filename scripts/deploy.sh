#!/bin/bash
set -e

echo "🚀 Starting Phylax Rollup Infrastructure Deployment"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

AWS_REGION=${AWS_REGION:-eu-west-1}
CLUSTER_NAME=${CLUSTER_NAME:-phylax-rollup}
DEPLOY_K8S_ONLY=${DEPLOY_K8S_ONLY:-false}

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
    
    echo "✅ All required dependencies are available"
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
    terraform init -upgrade
    
    echo "📋 Planning Terraform deployment..."
    terraform plan -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME"
    
    echo "🚀 Step 1: Creating EKS cluster infrastructure..."
    terraform apply -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME" -auto-approve \
        -target=module.vpc \
        -target=module.eks \
        -target=aws_iam_role.cluster_autoscaler \
        -target=aws_iam_policy.cluster_autoscaler \
        -target=aws_iam_role_policy_attachment.cluster_autoscaler \
        -target=aws_iam_role.aws_load_balancer_controller \
        -target=aws_iam_policy.aws_load_balancer_controller \
        -target=aws_iam_role_policy_attachment.aws_load_balancer_controller \
        -target=aws_iam_role.ebs_csi_driver \
        -target=aws_iam_role_policy_attachment.ebs_csi_driver \
        -target=aws_eks_access_entry.current_user \
        -target=aws_eks_access_policy_association.current_user_admin \
        -target=aws_eks_access_policy_association.current_user_cluster_admin
    
    echo "⏳ Waiting for EKS cluster to be fully ready..."
    # Get the cluster name
    CLUSTER_NAME_FULL=$(terraform output -raw cluster_name 2>/dev/null || echo "$CLUSTER_NAME")
    
    # Wait for the cluster to be ACTIVE
    while true; do
        status=$(aws eks describe-cluster --name "$CLUSTER_NAME_FULL" --region "$AWS_REGION" --query "cluster.status" --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$status" = "ACTIVE" ]; then
            echo "✅ EKS cluster $CLUSTER_NAME_FULL is active!"
            break
        else
            echo "⏳ EKS cluster status: $status. Waiting..."
            sleep 30
        fi
    done
    
    # Update kubeconfig
    echo "🔧 Updating kubeconfig..."
    aws eks update-kubeconfig --name "$CLUSTER_NAME_FULL" --region "$AWS_REGION"
    
    # EKS Access Entries are now managed via Terraform in cluster-auth.tf
    echo "✅ Cluster access is managed via EKS Access Entries in Terraform"
    
    # Test cluster connectivity
    echo "🔍 Testing cluster connectivity..."
    for i in {1..5}; do
        if kubectl get nodes >/dev/null 2>&1; then
            echo "✅ Successfully connected to cluster!"
            break
        else
            echo "⏳ Waiting for cluster API to be ready... (attempt $i/5)"
            sleep 10
            
            # If we're on the last attempt and still failing
            if [ $i -eq 5 ]; then
                echo "⚠️ Still facing connectivity issues. Verifying EKS Access Entries..."
                
                # Describe the cluster access entries
                aws eks list-access-entries --cluster-name "$CLUSTER_NAME_FULL" --region "$AWS_REGION"
                
                # Get the current caller identity
                CALLER_IDENTITY=$(aws sts get-caller-identity --query "Arn" --output text)
                echo "🔍 Current identity: $CALLER_IDENTITY"
                
                echo "⚠️ You may need to run terraform apply again to ensure access entries are properly configured."
                echo "⚠️ Check that your IAM user or role has proper permissions to access the EKS cluster."
            fi
        fi
    done
    
    # Additional wait to ensure all controllers are ready
    echo "⏳ Waiting 30 seconds for all cluster controllers to be ready..."
    sleep 30
    
    echo "📝 Getting outputs..."
    CLUSTER_NAME_FULL=$(terraform output -raw cluster_name)
    VPC_ID=$(terraform output -raw vpc_id)
    
    echo "✅ Terraform deployment completed"
    echo "📊 Cluster Name: $CLUSTER_NAME_FULL"
    echo "📊 VPC ID: $VPC_ID"
    
    cd "$PROJECT_ROOT"
}

deploy_addons() {
    echo "🚀 Deploying cluster add-ons (AWS Load Balancer Controller, Cluster Autoscaler, Prometheus)..."
    
    # Get IAM role ARNs from Terraform outputs
    cd "$PROJECT_ROOT/terraform"
    AWS_LB_CONTROLLER_ROLE_ARN=$(terraform output -raw aws_load_balancer_controller_role_arn)
    CLUSTER_AUTOSCALER_ROLE_ARN=$(terraform output -raw cluster_autoscaler_role_arn)
    cd "$PROJECT_ROOT"
    
    chmod +x "$PROJECT_ROOT/k8s/addons/install-addons.sh"
    "$PROJECT_ROOT/k8s/addons/install-addons.sh" "$CLUSTER_NAME" "$AWS_REGION" "$AWS_LB_CONTROLLER_ROLE_ARN" "$CLUSTER_AUTOSCALER_ROLE_ARN"
    
    echo "✅ Add-ons deployment completed"
}

deploy_kubernetes() {
    echo "☸️ Deploying Kubernetes resources..."
    
    # Add support for genesis-ssz.yaml
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
    
    if [ "$DEPLOY_K8S_ONLY" = "true" ]; then
        echo "🚀 Running Kubernetes-only deployment"
        # Skip AWS and Terraform but ensure kubectl is configured correctly
        if ! kubectl get nodes &>/dev/null; then
            echo "❌ Cannot connect to Kubernetes cluster. Please check your kubeconfig."
            exit 1
        fi
        
        deploy_kubernetes
        wait_for_services
        get_service_info
    else
        check_aws_credentials
        deploy_terraform
        deploy_addons
        deploy_kubernetes
        wait_for_services
        get_service_info
    fi
    
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
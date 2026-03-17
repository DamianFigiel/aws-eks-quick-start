#!/bin/bash
set -e
export AWS_PAGER=""

echo "🚀 Starting AWS EKS Cluster Deployment"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

AWS_REGION=${AWS_REGION:-eu-west-1}
CLUSTER_NAME=${CLUSTER_NAME:-eks-cluster}
DEPLOY_K8S_ONLY=${DEPLOY_K8S_ONLY:-false}
AWS_PROFILE_NAME=${AWS_PROFILE_NAME:-${CLUSTER_NAME}}

setup_aws_profile() {
    echo "🔧 Configuring AWS CLI profile '${AWS_PROFILE_NAME}'..."
    aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile "$AWS_PROFILE_NAME"
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile "$AWS_PROFILE_NAME"
    aws configure set region "$AWS_REGION" --profile "$AWS_PROFILE_NAME"
    export AWS_PROFILE="$AWS_PROFILE_NAME"
    echo "✅ AWS CLI profile '${AWS_PROFILE_NAME}' configured"
}

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
    
    if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
        setup_aws_profile
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ AWS credentials are not configured. Please check your .env file."
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
    
    echo "🚀 Applying Terraform configuration..."
    terraform apply -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME" -auto-approve
    
    echo "⏳ Waiting for EKS cluster to be fully ready..."
    CLUSTER_NAME_FULL=$(terraform output -raw cluster_name 2>/dev/null || echo "$CLUSTER_NAME")
    
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
    
    echo "🔧 Updating kubeconfig..."
    aws eks update-kubeconfig --name "$CLUSTER_NAME_FULL" --region "$AWS_REGION" --profile "$AWS_PROFILE_NAME"
    
    echo "✅ Cluster access is managed via EKS Access Entries in Terraform"
    
    echo "🔍 Testing cluster connectivity..."
    for i in {1..5}; do
        if kubectl get nodes >/dev/null 2>&1; then
            echo "✅ Successfully connected to cluster!"
            break
        else
            echo "⏳ Waiting for cluster API to be ready... (attempt $i/5)"
            sleep 10
            
            if [ $i -eq 5 ]; then
                echo "⚠️ Still facing connectivity issues. Verifying EKS Access Entries..."
                aws eks list-access-entries --cluster-name "$CLUSTER_NAME_FULL" --region "$AWS_REGION"
                CALLER_IDENTITY=$(aws sts get-caller-identity --query "Arn" --output text)
                echo "🔍 Current identity: $CALLER_IDENTITY"
                echo "⚠️ You may need to run terraform apply again to ensure access entries are properly configured."
            fi
        fi
    done
    
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
    
    cd "$PROJECT_ROOT/terraform"
    AWS_LB_CONTROLLER_ROLE_ARN=$(terraform output -raw aws_load_balancer_controller_role_arn)
    CLUSTER_AUTOSCALER_ROLE_ARN=$(terraform output -raw cluster_autoscaler_role_arn)
    cd "$PROJECT_ROOT"
    
    chmod +x "$PROJECT_ROOT/k8s/addons/install-addons.sh"
    "$PROJECT_ROOT/k8s/addons/install-addons.sh" "$CLUSTER_NAME" "$AWS_REGION" "$AWS_LB_CONTROLLER_ROLE_ARN" "$CLUSTER_AUTOSCALER_ROLE_ARN"
    
    echo "✅ Add-ons deployment completed"
}

run_verification() {
    echo ""
    echo "🔍 Running post-deployment verification..."
    echo ""
    chmod +x "$PROJECT_ROOT/scripts/verify.sh"
    "$PROJECT_ROOT/scripts/verify.sh" || true
}

main() {
    check_dependencies
    
    if [ "$DEPLOY_K8S_ONLY" = "true" ]; then
        echo "🚀 Running add-ons only deployment"
        if ! kubectl get nodes &>/dev/null; then
            echo "❌ Cannot connect to Kubernetes cluster. Please check your kubeconfig."
            exit 1
        fi
        
        deploy_addons
    else
        check_aws_credentials
        deploy_terraform
        deploy_addons
    fi
    
    run_verification
    
    echo ""
    echo "🎉 AWS EKS Cluster deployment completed successfully!"
    echo ""
    echo "📋 Next steps:"
    echo "1. Your EKS cluster is ready for use"
    echo "2. Cluster autoscaler is configured to scale nodes automatically"
    echo "3. AWS Load Balancer Controller is ready for LoadBalancer services"
    echo "4. Monitoring stack (Prometheus/Grafana) is deployed"
    echo "5. Pod logs and metrics are streaming to CloudWatch"
    echo ""
    echo "🔧 Useful commands:"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
    echo "  make verify        # Re-run verification"
    echo "  make status         # Show cluster status"
    echo "  make destroy        # Tear down everything"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

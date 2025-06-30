#!/bin/bash
set -e

echo "🗑️ Starting Phylax Rollup Infrastructure Destruction"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

AWS_REGION=${AWS_REGION:-eu-west-1}
CLUSTER_NAME=${CLUSTER_NAME:-phylax-rollup}

confirm_destruction() {
    echo "⚠️  WARNING: This will destroy all infrastructure and data!"
    echo "⚠️  This action cannot be undone!"
    echo ""
    read -p "Type 'destroy' to confirm: " confirm
    
    if [[ "$confirm" != "destroy" ]]; then
        echo "❌ Destruction cancelled"
        exit 1
    fi
}

cleanup_kubernetes() {
    echo "☸️ Cleaning up Kubernetes resources..."
    
    echo "🗑️ Removing monitoring..."
    kubectl delete -f "$PROJECT_ROOT/k8s/monitoring.yaml" --ignore-not-found=true
    
    echo "🗑️ Removing rollup infrastructure..."
    kubectl delete -f "$PROJECT_ROOT/k8s/op-node.yaml" --ignore-not-found=true
    kubectl delete -f "$PROJECT_ROOT/k8s/op-geth.yaml" --ignore-not-found=true
    
    echo "🗑️ Removing Ethereum infrastructure..."
    kubectl delete -f "$PROJECT_ROOT/k8s/ethereum-beacon.yaml" --ignore-not-found=true
    kubectl delete -f "$PROJECT_ROOT/k8s/ethereum-execution.yaml" --ignore-not-found=true
    
    echo "🗑️ Removing persistent volumes..."
    kubectl delete -f "$PROJECT_ROOT/k8s/persistent-volumes.yaml" --ignore-not-found=true
    
    echo "🗑️ Removing ConfigMaps and Secrets..."
    kubectl delete -f "$PROJECT_ROOT/k8s/configmaps.yaml" --ignore-not-found=true
    
    echo "🗑️ Removing namespaces..."
    kubectl delete -f "$PROJECT_ROOT/k8s/namespaces.yaml" --ignore-not-found=true
    
    echo "⏳ Waiting for resources to be deleted..."
    sleep 30
    
    echo "✅ Kubernetes cleanup completed"
}

destroy_terraform() {
    echo "🏗️ Destroying Terraform infrastructure..."
    
    cd "$PROJECT_ROOT/terraform"
    
    echo "🗑️ Destroying Terraform resources..."
    terraform destroy -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME" -auto-approve
    
    echo "✅ Terraform destruction completed"
    
    cd "$PROJECT_ROOT"
}

cleanup_local() {
    echo "🧹 Cleaning up local files..."
    
    if [ -d "$PROJECT_ROOT/terraform/.terraform" ]; then
        rm -rf "$PROJECT_ROOT/terraform/.terraform"
    fi
    
    if [ -f "$PROJECT_ROOT/terraform/terraform.tfstate" ]; then
        rm -f "$PROJECT_ROOT/terraform/terraform.tfstate"
    fi
    
    if [ -f "$PROJECT_ROOT/terraform/terraform.tfstate.backup" ]; then
        rm -f "$PROJECT_ROOT/terraform/terraform.tfstate.backup"
    fi
    
    echo "✅ Local cleanup completed"
}

main() {
    confirm_destruction
    
    # if kubectl cluster-info &> /dev/null; then
    #     cleanup_kubernetes
    # else
    #     echo "⚠️ No active kubectl context found, skipping Kubernetes cleanup"
    # fi
    
    if [ -f "$PROJECT_ROOT/terraform/terraform.tfstate" ] || [ -d "$PROJECT_ROOT/terraform/.terraform" ]; then
        destroy_terraform
    else
        echo "⚠️ No Terraform state found, skipping Terraform destruction"
    fi
    
    cleanup_local
    
    echo ""
    echo "🎉 Phylax Rollup Infrastructure destruction completed!"
    echo ""
    echo "Remember to remove the Kubernetes context in ~/.kube/config"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
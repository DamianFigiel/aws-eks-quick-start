#!/bin/bash
set -e

echo "🗑️ Starting AWS EKS Cluster Destruction"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

AWS_REGION=${AWS_REGION:-eu-west-1}
CLUSTER_NAME=${CLUSTER_NAME:-eks-cluster}

check_dependencies() {
    echo "🔍 Checking dependencies..."
    
    if ! command -v terraform &> /dev/null; then
        echo "❌ Terraform is not installed. Please install Terraform."
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI is not installed. Please install AWS CLI."
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

cleanup_addons() {
    echo "🗑️ Cleaning up cluster add-ons..."
    
    # Check if kubectl is available and cluster is accessible
    if command -v kubectl &> /dev/null; then
        if kubectl get nodes &>/dev/null; then
            echo "🗑️ Uninstalling Helm releases..."
            
            # Uninstall Prometheus stack
            if helm list -n monitoring | grep -q prometheus; then
                echo "🗑️ Uninstalling Prometheus..."
                helm uninstall prometheus -n monitoring
            fi
            
            # Uninstall Cluster Autoscaler
            if helm list -n kube-system | grep -q cluster-autoscaler; then
                echo "🗑️ Uninstalling Cluster Autoscaler..."
                helm uninstall cluster-autoscaler -n kube-system
            fi
            
            # Uninstall AWS Load Balancer Controller
            if helm list -n kube-system | grep -q aws-load-balancer-controller; then
                echo "🗑️ Uninstalling AWS Load Balancer Controller..."
                helm uninstall aws-load-balancer-controller -n kube-system
            fi
            
            echo "✅ Add-ons cleanup completed"
        else
            echo "⚠️ Cannot connect to cluster, skipping add-ons cleanup"
        fi
    else
        echo "⚠️ kubectl not available, skipping add-ons cleanup"
    fi
}

cleanup_external_resources() {
    echo "🗑️ Cleaning up external AWS resources..."
    
    # Get cluster name and region from terraform state or variables
    CLUSTER_NAME_FULL=${CLUSTER_NAME:-eks-cluster}
    AWS_REGION_FULL=${AWS_REGION:-eu-west-1}
    
    # Get VPC ID from terraform state
    cd "$PROJECT_ROOT/terraform"
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    cd "$PROJECT_ROOT"
    
    if [ -n "$VPC_ID" ]; then
        echo "🔍 Found VPC: $VPC_ID"
        
        # Delete Load Balancers created by AWS Load Balancer Controller
        echo "🗑️ Cleaning up Load Balancers..."
        LB_ARNS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null || echo "")
        
        if [ -n "$LB_ARNS" ]; then
            echo "Found Load Balancers: $LB_ARNS"
            for LB_ARN in $LB_ARNS; do
                echo "Deleting Load Balancer: $LB_ARN"
                aws elbv2 delete-load-balancer --load-balancer-arn "$LB_ARN" 2>/dev/null || echo "Failed to delete LB: $LB_ARN"
            done
            
            # Wait for Load Balancers to be deleted
            echo "⏳ Waiting for Load Balancers to be deleted..."
            sleep 30
        else
            echo "No Load Balancers found"
        fi
        
        # Delete Security Groups created by AWS Load Balancer Controller
        echo "🗑️ Cleaning up Security Groups..."
        SG_IDS=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=k8s-*" \
            --query "SecurityGroups[?GroupName!='default'].GroupId" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SG_IDS" ]; then
            echo "Found Security Groups: $SG_IDS"
            for SG_ID in $SG_IDS; do
                echo "Cleaning up Security Group: $SG_ID"
                
                # Remove all ingress rules
                INGRESS_RULES=$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
                    --query "SecurityGroups[0].IpPermissions" --output json 2>/dev/null || echo "[]")
                
                if [ "$INGRESS_RULES" != "[]" ]; then
                    echo "Removing ingress rules from $SG_ID"
                    aws ec2 revoke-security-group-ingress --group-id "$SG_ID" --ip-permissions "$INGRESS_RULES" 2>/dev/null || echo "Failed to remove ingress rules"
                fi
                
                # Remove all egress rules (except default)
                EGRESS_RULES=$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
                    --query "SecurityGroups[0].IpPermissionsEgress[?IpProtocol!='-1']" --output json 2>/dev/null || echo "[]")
                
                if [ "$EGRESS_RULES" != "[]" ]; then
                    echo "Removing egress rules from $SG_ID"
                    aws ec2 revoke-security-group-egress --group-id "$SG_ID" --ip-permissions "$EGRESS_RULES" 2>/dev/null || echo "Failed to remove egress rules"
                fi
                
                # Delete the security group
                echo "Deleting Security Group: $SG_ID"
                aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null || echo "Failed to delete SG: $SG_ID"
            done
        else
            echo "No external Security Groups found"
        fi
        
        # Delete Network Interfaces that might be left
        echo "🗑️ Cleaning up Network Interfaces..."
        ENI_IDS=$(aws ec2 describe-network-interfaces \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" \
            --query "NetworkInterfaces[?Description=='ELB *' || Description=='AWS Load Balancer *'].NetworkInterfaceId" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$ENI_IDS" ]; then
            echo "Found Network Interfaces: $ENI_IDS"
            for ENI_ID in $ENI_IDS; do
                echo "Deleting Network Interface: $ENI_ID"
                aws ec2 delete-network-interface --network-interface-id "$ENI_ID" 2>/dev/null || echo "Failed to delete ENI: $ENI_ID"
            done
        else
            echo "No external Network Interfaces found"
        fi
        
        echo "✅ External resources cleanup completed"
    else
        echo "⚠️ Could not determine VPC ID, trying to find VPC by cluster name..."
        cleanup_by_cluster_name
    fi
}

cleanup_by_cluster_name() {
    echo "🔍 Searching for VPC by cluster name: $CLUSTER_NAME_FULL"
    
    # Try to find VPC by cluster name in tags
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME_FULL,Values=owned" \
        --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "")
    
    if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
        echo "🔍 Found VPC by cluster tag: $VPC_ID"
        # Recursively call cleanup with the found VPC ID
        VPC_ID_FOUND="$VPC_ID"
        cleanup_external_resources
    else
        echo "⚠️ Could not find VPC by cluster name, skipping external resources cleanup"
    fi
}

destroy_terraform() {
    echo "🗑️ Destroying Terraform infrastructure..."
    
    cd "$PROJECT_ROOT/terraform"
    
    echo "📋 Planning Terraform destruction..."
    terraform plan -destroy -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME"
    
    echo "⚠️ This will destroy all AWS resources including the EKS cluster."
    echo "⚠️ This action cannot be undone!"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        echo "🗑️ Destroying infrastructure..."
        terraform destroy -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME" -auto-approve
        
        echo "✅ Terraform destruction completed"
    else
        echo "❌ Destruction cancelled"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
}

main() {
    check_dependencies
    check_aws_credentials
    
    echo "⚠️ Starting destruction process for cluster: $CLUSTER_NAME in region: $AWS_REGION"
    
    cleanup_addons
    cleanup_external_resources
    destroy_terraform
    
    echo ""
    echo "🎉 AWS EKS Cluster destruction completed successfully!"
    echo ""
    echo "📋 What was destroyed:"
    echo "1. EKS cluster and all node groups"
    echo "2. VPC and networking resources"
    echo "3. IAM roles and policies"
    echo "4. All cluster add-ons (Prometheus, Cluster Autoscaler, Load Balancer Controller)"
    echo ""
    echo "⚠️ Note: Any persistent volumes created outside of this Terraform configuration"
    echo "   may still exist and need to be manually cleaned up."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
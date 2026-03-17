#!/bin/bash
set -e
export AWS_PAGER=""

echo "🗑️ Starting AWS EKS Cluster Destruction"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

FORCE=false
for arg in "$@"; do
  case $arg in
    --force) FORCE=true ;;
  esac
done

AWS_REGION=${AWS_REGION:-eu-west-1}
CLUSTER_NAME=${CLUSTER_NAME:-eks-cluster}
AWS_PROFILE_NAME=${AWS_PROFILE_NAME:-${CLUSTER_NAME}}

if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile "$AWS_PROFILE_NAME"
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile "$AWS_PROFILE_NAME"
    aws configure set region "$AWS_REGION" --profile "$AWS_PROFILE_NAME"
    export AWS_PROFILE="$AWS_PROFILE_NAME"
fi

check_dependencies() {
    echo "🔍 Checking dependencies..."
    command -v terraform &> /dev/null || { echo "❌ Terraform is not installed."; exit 1; }
    command -v aws &> /dev/null || { echo "❌ AWS CLI is not installed."; exit 1; }
    echo "✅ All required dependencies are available"
}

check_aws_credentials() {
    echo "🔍 Checking AWS credentials..."
    aws sts get-caller-identity &> /dev/null || { echo "❌ AWS credentials are not configured."; exit 1; }
    echo "✅ AWS credentials are configured"
}

get_vpc_id() {
    cd "$PROJECT_ROOT/terraform"
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    cd "$PROJECT_ROOT"

    if [ -z "$VPC_ID" ]; then
        VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned,shared" \
            --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
        [ "$VPC_ID" = "None" ] && VPC_ID=""
    fi

    echo "$VPC_ID"
}

cleanup_addons() {
    echo "🗑️ Cleaning up cluster add-ons..."
    if command -v kubectl &> /dev/null && kubectl get nodes &>/dev/null; then
        for release_ns in "prometheus:monitoring" "cluster-autoscaler:kube-system" "aws-load-balancer-controller:kube-system"; do
            release=$(echo "$release_ns" | cut -d: -f1)
            ns=$(echo "$release_ns" | cut -d: -f2)
            if helm list -n "$ns" 2>/dev/null | grep -q "$release"; then
                echo "  Uninstalling $release..."
                helm uninstall "$release" -n "$ns" --wait 2>/dev/null || true
            fi
        done
        echo "✅ Add-ons cleanup completed"
    else
        echo "⚠️ Cannot connect to cluster, skipping add-ons cleanup"
    fi
}

cleanup_vpc_dependencies() {
    local vpc_id=$1
    [ -z "$vpc_id" ] && return

    echo "🗑️ Cleaning up all VPC dependencies for $vpc_id..."

    echo "  Deleting load balancers..."
    LB_ARNS=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?VpcId=='$vpc_id'].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")
    for arn in $LB_ARNS; do
        echo "    Deleting ALB/NLB: $arn"
        aws elbv2 delete-load-balancer --load-balancer-arn "$arn" 2>/dev/null || true
    done

    CLB_NAMES=$(aws elb describe-load-balancers \
        --query "LoadBalancerDescriptions[?VPCId=='$vpc_id'].LoadBalancerName" \
        --output text 2>/dev/null || echo "")
    for name in $CLB_NAMES; do
        echo "    Deleting CLB: $name"
        aws elb delete-load-balancer --load-balancer-name "$name" 2>/dev/null || true
    done

    if [ -n "$LB_ARNS" ] || [ -n "$CLB_NAMES" ]; then
        echo "  ⏳ Waiting 30s for load balancers to release ENIs..."
        sleep 30
    fi

    echo "  Detaching and deleting ENIs..."
    ALL_ENI_IDS=$(aws ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query "NetworkInterfaces[].NetworkInterfaceId" \
        --output text 2>/dev/null || echo "")
    for eni_id in $ALL_ENI_IDS; do
        ENI_STATUS=$(aws ec2 describe-network-interfaces \
            --network-interface-ids "$eni_id" \
            --query "NetworkInterfaces[0].Status" \
            --output text 2>/dev/null || echo "gone")
        [ "$ENI_STATUS" = "gone" ] && continue

        if [ "$ENI_STATUS" = "in-use" ]; then
            ATTACH_ID=$(aws ec2 describe-network-interfaces \
                --network-interface-ids "$eni_id" \
                --query "NetworkInterfaces[0].Attachment.AttachmentId" \
                --output text 2>/dev/null || echo "")
            if [ -n "$ATTACH_ID" ] && [ "$ATTACH_ID" != "None" ]; then
                echo "    Detaching ENI $eni_id ($ATTACH_ID)..."
                aws ec2 detach-network-interface --attachment-id "$ATTACH_ID" --force 2>/dev/null || true
            fi
        fi
    done

    if [ -n "$ALL_ENI_IDS" ]; then
        echo "  ⏳ Waiting 15s for ENIs to detach..."
        sleep 15
    fi

    for eni_id in $ALL_ENI_IDS; do
        aws ec2 delete-network-interface --network-interface-id "$eni_id" 2>/dev/null || true
    done

    echo "  Deleting non-default security groups..."
    SG_IDS=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" \
        --output text 2>/dev/null || echo "")
    for sg_id in $SG_IDS; do
        INGRESS=$(aws ec2 describe-security-groups --group-ids "$sg_id" \
            --query "SecurityGroups[0].IpPermissions" --output json 2>/dev/null || echo "[]")
        [ "$INGRESS" != "[]" ] && \
            aws ec2 revoke-security-group-ingress --group-id "$sg_id" --ip-permissions "$INGRESS" 2>/dev/null || true

        EGRESS=$(aws ec2 describe-security-groups --group-ids "$sg_id" \
            --query "SecurityGroups[0].IpPermissionsEgress" --output json 2>/dev/null || echo "[]")
        [ "$EGRESS" != "[]" ] && \
            aws ec2 revoke-security-group-egress --group-id "$sg_id" --ip-permissions "$EGRESS" 2>/dev/null || true
    done
    for sg_id in $SG_IDS; do
        aws ec2 delete-security-group --group-id "$sg_id" 2>/dev/null || true
    done

    echo "✅ VPC dependency cleanup completed"
}

destroy_terraform() {
    cd "$PROJECT_ROOT/terraform"

    echo "📋 Planning Terraform destruction..."
    terraform plan -destroy -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME"

    echo "⚠️ This will destroy all AWS resources including the EKS cluster."
    echo "⚠️ This action cannot be undone!"

    if [ "$FORCE" = "true" ]; then
        echo "🔧 --force flag detected, skipping confirmation"
    else
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "❌ Destruction cancelled"
            exit 1
        fi
    fi

    echo "🗑️ Destroying infrastructure..."
    if terraform destroy -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME" -auto-approve; then
        echo "✅ Terraform destruction completed"
    else
        echo "⚠️ Terraform destroy failed (likely VPC dependency issue). Cleaning up and retrying..."

        local vpc_id
        vpc_id=$(get_vpc_id)
        if [ -n "$vpc_id" ]; then
            cleanup_vpc_dependencies "$vpc_id"
            echo "🔄 Retrying terraform destroy..."
            terraform destroy -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME" -auto-approve
            echo "✅ Terraform destruction completed on retry"
        else
            echo "❌ Could not determine VPC ID for cleanup. Manual intervention needed."
            exit 1
        fi
    fi

    cd "$PROJECT_ROOT"
}

main() {
    check_dependencies
    check_aws_credentials

    echo "⚠️ Starting destruction process for cluster: $CLUSTER_NAME in region: $AWS_REGION"

    local vpc_id
    vpc_id=$(get_vpc_id)

    cleanup_addons

    if [ -n "$vpc_id" ]; then
        cleanup_vpc_dependencies "$vpc_id"
    fi

    destroy_terraform

    echo "🔧 Removing cluster from local kubeconfig..."
    CONTEXT="arn:aws:eks:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text 2>/dev/null):cluster/${CLUSTER_NAME}"
    kubectl config unset "users.${CONTEXT}" 2>/dev/null || true
    kubectl config unset "clusters.${CONTEXT}" 2>/dev/null || true
    kubectl config delete-context "${CONTEXT}" 2>/dev/null || true
    echo "✅ Cluster removed from kubeconfig"

    echo "🔧 Removing AWS CLI profile '${AWS_PROFILE_NAME}'..."
    aws configure set aws_access_key_id "" --profile "$AWS_PROFILE_NAME" 2>/dev/null || true
    aws configure set aws_secret_access_key "" --profile "$AWS_PROFILE_NAME" 2>/dev/null || true
    rm -f ~/.aws/cli/cache/*"$AWS_PROFILE_NAME"* 2>/dev/null || true
    echo "✅ AWS CLI profile cleaned up"

    echo ""
    echo "🎉 AWS EKS Cluster destruction completed successfully!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

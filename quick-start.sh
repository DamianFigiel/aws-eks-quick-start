#!/bin/bash

set -e

echo "🚀 AWS EKS Cluster Quick Start"
echo "=============================="
echo ""

# Check if terraform.tfvars already exists
if [ -f "terraform/terraform.tfvars" ]; then
    echo "⚠️  terraform/terraform.tfvars already exists!"
    echo "   If you want to start fresh, please backup and remove it first."
    echo ""
    read -p "Do you want to continue with existing configuration? (y/N): " continue_existing
    
    if [[ ! "$continue_existing" =~ ^[Yy]$ ]]; then
        echo "❌ Setup cancelled. Please backup and remove terraform/terraform.tfvars to start fresh."
        exit 1
    fi
else
    echo "📝 Setting up configuration..."
    cp terraform/terraform.tfvars.example terraform/terraform.tfvars
    echo "✅ Created terraform/terraform.tfvars from example"
    echo ""
    echo "📋 Please edit terraform/terraform.tfvars with your desired configuration:"
    echo "   - Set your cluster name"
    echo "   - Configure instance types and sizes"
    echo "   - Update tags and project information"
    echo ""
    read -p "Press Enter when you're ready to continue..."
fi

# Check dependencies
echo ""
echo "🔍 Checking dependencies..."
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install Terraform first."
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install AWS CLI first."
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed. Please install Helm first."
    exit 1
fi

echo "✅ All dependencies are available"

# Check AWS credentials
echo ""
echo "🔍 Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials are not configured. Please run 'aws configure' first."
    exit 1
fi

echo "✅ AWS credentials are configured"

# Get cluster name from terraform.tfvars
CLUSTER_NAME=$(grep 'cluster_name' terraform/terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
AWS_REGION=$(grep 'aws_region' terraform/terraform.tfvars | cut -d'=' -f2 | tr -d ' "')

echo ""
echo "📊 Configuration Summary:"
echo "   Cluster Name: $CLUSTER_NAME"
echo "   AWS Region: $AWS_REGION"
echo ""

read -p "Do you want to proceed with deployment? (y/N): " proceed

if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled."
    exit 1
fi

echo ""
echo "🚀 Starting deployment..."
echo "=========================="

# Run the deployment
make deploy

echo ""
echo "🎉 Deployment completed!"
echo ""
echo "📋 Next steps:"
echo "1. Check cluster status: make status"
echo "2. Access Grafana: make port-forward-grafana"
echo "3. Test connectivity: make test-connectivity"
echo ""
echo "📚 For more information, see README.md"

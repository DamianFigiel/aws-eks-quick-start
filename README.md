# AWS EKS Cluster Provisioning Tool

A comprehensive Terraform-based tool for provisioning AWS EKS clusters with essential add-ons and monitoring capabilities.

## Features

- **EKS Cluster**: Production-ready Kubernetes cluster with latest version (1.33)
- **Node Groups**: Auto-scaling node groups with spot and on-demand instances
- **IAM Integration**: IAM Roles for Service Accounts (IRSA) enabled
- **Essential Add-ons**:
  - AWS Load Balancer Controller
  - Cluster Autoscaler
  - EBS CSI Driver
  - Prometheus + Grafana monitoring stack
- **Security**: EKS Access Entries for modern authentication
- **Networking**: VPC with proper subnets and security groups

## Prerequisites

### 1. Required Tools

You need to install the following tools:

```bash
# Install Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs)"
sudo apt-get update && sudo apt-get install terraform

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 2. AWS Configuration

Configure your AWS credentials:

```bash
aws configure
```

You'll need to provide:
- AWS Access Key ID
- AWS Secret Access Key
- Default region (e.g., eu-west-1)
- Default output format (json)

### 3. Required AWS Permissions

Your AWS user/role needs the following permissions:
- EKS full access
- EC2 full access
- IAM full access
- VPC full access
- EBS full access

## Quick Start

### Option A: Automated Setup (Recommended)

Use the quick start script for an interactive setup:

```bash
git clone <repository-url>
cd <repository-name>
./quick-start.sh
```

The script will:
- Check all dependencies
- Verify AWS credentials
- Create configuration from template
- Guide you through customization
- Deploy the cluster

### Option B: Manual Setup

### 1. Clone and Configure

```bash
git clone <repository-url>
cd <repository-name>

# Option A: Use the quick start script (recommended)
./quick-start.sh

# Option B: Manual configuration
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

### 2. Customize Configuration

Edit `terraform/terraform.tfvars` with your desired settings:

```hcl
aws_region      = "eu-west-1"
cluster_name    = "my-eks-cluster"
cluster_version = "1.33"

node_group_instance_types = ["m6i.xlarge"]
min_size                  = 2
max_size                  = 10
desired_size              = 3

common_tags = {
  Environment = "production"
  Project     = "my-project"
  ManagedBy   = "terraform"
  Owner       = "platform-team"
}
```

### 3. Deploy Infrastructure

Deploy the complete EKS cluster with all add-ons:

```bash
make deploy
```

This will:
1. Create VPC and networking resources
2. Deploy EKS cluster with node groups
3. Configure IAM roles and policies
4. Install cluster add-ons (Load Balancer Controller, Cluster Autoscaler, Prometheus)

### 4. Deploy Add-ons Only (if cluster already exists)

If you already have an EKS cluster and just want to install the add-ons:

```bash
make deploy-addons
```

## Usage

### Check Status

```bash
make status
```

### Access Grafana

```bash
make port-forward-grafana
# Then visit http://localhost:3000 (admin/admin)
```

### Test Connectivity

```bash
make test-connectivity
```

### View Logs

```bash
make logs
```

### Clean Up

```bash
# Full cleanup (recommended)
make destroy

# Clean up external resources only (if destroy fails)
make cleanup-external
```

## Configuration Options

### Cluster Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `cluster_name` | Name of the EKS cluster | `eks-cluster` |
| `cluster_version` | Kubernetes version | `1.33` |
| `aws_region` | AWS region | `eu-west-1` |

### Node Group Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `node_group_instance_types` | EC2 instance types | `["m6i.xlarge"]` |
| `min_size` | Minimum nodes | `2` |
| `max_size` | Maximum nodes | `10` |
| `desired_size` | Desired nodes | `3` |

### Add-ons Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_cluster_autoscaler` | Enable cluster autoscaler | `true` |
| `enable_aws_load_balancer_controller` | Enable Load Balancer Controller | `true` |
| `enable_ebs_csi_driver` | Enable EBS CSI Driver | `true` |
| `enable_monitoring` | Enable Prometheus/Grafana | `true` |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS EKS Cluster                      │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │   Node Group 1  │  │   Node Group 2  │  │   Node Group │ │
│  │  (On-Demand)    │  │    (Spot)       │  │   (System)   │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                    EKS Add-ons                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │ Cluster         │  │ AWS Load        │  │ EBS CSI      │ │
│  │ Autoscaler      │  │ Balancer        │  │ Driver       │ │
│  │                 │  │ Controller      │  │              │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                    Monitoring Stack                         │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │   Prometheus    │  │     Grafana     │                  │
│  │                 │  │                 │                  │
│  └─────────────────┘  └─────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

## Cost Estimation

Monthly cost estimate for default configuration:
- **EKS Control Plane**: ~$73/month
- **Node Groups** (3x m6i.xlarge): ~$438/month
- **Load Balancers**: ~$18/month
- **EBS Volumes**: ~$50/month
- **Data Transfer**: ~$20/month
- **Total**: ~$599/month

*Costs may vary based on usage, region, and instance types.*

## Troubleshooting

### Common Issues

1. **Cluster not accessible**
   ```bash
   aws eks update-kubeconfig --name <cluster-name> --region <region>
   ```

2. **Add-ons not working**
   ```bash
   make clean-addons
   make deploy-addons
   ```

3. **Terraform state issues**
   ```bash
   make clean
   make deploy
   ```

4. **Destroy fails due to external resources**
   ```bash
   # Clean up external resources first
   make cleanup-external
   # Then try destroy again
   make destroy
   ```

### Useful Commands

```bash
# Check cluster status
kubectl get nodes

# Check add-ons
kubectl get pods -A

# Check services
kubectl get svc -A

# View logs
kubectl logs -f <pod-name> -n <namespace>
```

## Security

- EKS Access Entries for modern authentication
- IAM Roles for Service Accounts (IRSA)
- Encrypted EBS volumes
- Security groups with minimal required access
- Private subnets for worker nodes

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License.

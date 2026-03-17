# EKS Accelerator

Spin up a fully configured EKS cluster with one command. Tear it down with one command.

## What It Creates

- **EKS Cluster** (v1.33) with a general-purpose managed node group (configurable size/instance types)
- **Optional Fargate profiles** for serverless pod execution
- **VPC** with public/private subnets across 3 AZs, NAT gateways
- **EKS Add-ons**: CoreDNS, kube-proxy, VPC CNI, EBS CSI Driver, CloudWatch Observability
- **Helm Add-ons**: AWS Load Balancer Controller, Cluster Autoscaler, Prometheus + Grafana
- **CloudWatch**: Container Insights metrics, pod logs via Fluent Bit, control plane logs
- **IAM**: IRSA roles for all components, EKS Access Entries for cluster auth
- **Local kubectl** configured automatically

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.7
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)

## Setup

1. Add your AWS credentials to `.env`:

```
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
AWS_REGION=eu-west-1
```

2. Optionally customize settings:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform/terraform.tfvars
```

## Usage

```bash
make deploy              # Deploy everything
make verify              # Verify cluster, CloudWatch logs & metrics
make destroy             # Tear down (interactive confirmation)
make destroy FORCE=true  # Tear down (no confirmation)
```

## Other Commands

```bash
make status              # Show cluster/nodes/pods/services
make deploy-addons       # Re-deploy Helm add-ons only
make plan                # Terraform plan (dry run)
make format              # Format Terraform files
make clean-addons        # Uninstall Helm add-ons
```

## Configuration

Key variables in `terraform/terraform.tfvars`:

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_name` | `eks-cluster` | EKS cluster name |
| `cluster_version` | `1.33` | Kubernetes version |
| `aws_region` | `eu-west-1` | AWS region |
| `node_group_instance_types` | `["m6i.xlarge"]` | EC2 instance types |
| `min_size` / `max_size` / `desired_size` | `2` / `10` / `3` | Node group scaling |
| `enable_fargate` | `false` | Enable Fargate profiles |
| `fargate_namespaces` | `["default", "kube-system"]` | Namespaces for Fargate |
| `enable_cloudwatch_observability` | `true` | CloudWatch logs + metrics |
| `enable_monitoring` | `true` | Prometheus + Grafana stack |

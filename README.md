# Phylax Rollup Infrastructure

A production-ready, high-availability Ethereum rollup infrastructure deployed on AWS EKS using Terraform and Kubernetes.

## 🏗️ Architecture

This infrastructure deploys a complete Ethereum rollup stack including:

### Core Components
- **Ethereum Execution Layer**: Geth client for L1 connectivity
- **Ethereum Consensus Layer**: Prysm beacon chain client
- **OP-Geth**: Optimism execution engine for L2
- **OP-Node**: Optimism consensus/rollup node for L2

### Infrastructure Components
- **AWS EKS**: Managed Kubernetes cluster with auto-scaling
- **VPC**: Multi-AZ setup with public/private subnets
- **EBS CSI**: High-performance storage for blockchain data
- **ALB/NLB**: Load balancers for external access
- **Monitoring**: Prometheus + Grafana stack
- **IAM**: Least-privilege security with IRSA

## 📋 Prerequisites

### Required Tools
- [Terraform](https://terraform.io/) >= 1.0
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- [Helm](https://helm.sh/) >= 3.0

### AWS Configuration
```bash
aws configure
# Ensure you have appropriate IAM permissions for EKS, VPC, IAM, etc.
```

## 🚀 Quick Start

### 1. Clone and Configure
```bash
git clone <repository-url>
cd phylax-rollup-infrastructure

# Copy and customize variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform/terraform.tfvars with your preferences
```

### 2. Deploy Infrastructure
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Deploy everything
./scripts/deploy.sh
```

### 3. Access Services
```bash
# Get LoadBalancer endpoint for rollup RPC
kubectl get svc -n rollup op-geth-external

# Access Grafana (default: admin/admin)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

## 🗂️ Project Structure

```
├── terraform/               # Infrastructure as Code
│   ├── main.tf             # Main Terraform configuration
│   ├── variables.tf        # Input variables
│   ├── outputs.tf          # Output values
│   ├── vpc.tf              # VPC and networking
│   ├── eks.tf              # EKS cluster configuration
│   ├── iam.tf              # IAM roles and policies
│   └── addons.tf           # EKS add-ons and Helm charts
├── k8s/                    # Kubernetes manifests
│   ├── namespaces.yaml     # Kubernetes namespaces
│   ├── configmaps.yaml     # Configuration data
│   ├── persistent-volumes.yaml # Storage claims
│   ├── ethereum-execution.yaml # L1 execution client
│   ├── ethereum-beacon.yaml    # L1 consensus client
│   ├── op-geth.yaml        # L2 execution engine
│   ├── op-node.yaml        # L2 rollup node
│   └── monitoring.yaml     # Monitoring configuration
├── scripts/                # Deployment automation
│   ├── deploy.sh           # Full deployment script
│   └── destroy.sh          # Cleanup script
└── README.md               # This file
```

## 🔧 Configuration

### Terraform Variables

Key variables in `terraform/terraform.tfvars`:

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for deployment | `us-west-2` |
| `cluster_name` | EKS cluster name | `phylax-rollup` |
| `cluster_version` | Kubernetes version | `1.28` |
| `node_group_instance_types` | EC2 instance types | `["m6i.xlarge", "m5.xlarge"]` |
| `min_size` | Minimum nodes | `2` |
| `max_size` | Maximum nodes | `10` |
| `desired_size` | Desired nodes | `3` |

### Kubernetes Configuration

The infrastructure creates two main namespaces:
- `ethereum`: L1 Ethereum nodes
- `rollup`: L2 Optimism rollup components

## 📊 Monitoring

### Grafana Dashboards
- **Rollup Infrastructure**: Overview of rollup components
- **Kubernetes Cluster**: EKS cluster metrics
- **Node Metrics**: Individual component performance

### Key Metrics
- Block height synchronization
- Transaction throughput
- Node health and connectivity
- Resource utilization

### Accessing Monitoring
```bash
# Port-forward to Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Default credentials: admin/admin
open http://localhost:3000
```

## 🔐 Security

### Network Security
- Private subnets for worker nodes
- Security groups with minimal required access
- No direct internet access for blockchain nodes

### IAM Security
- IAM Roles for Service Accounts (IRSA)
- Least-privilege principle
- No long-term access keys

### Storage Security
- Encrypted EBS volumes
- Persistent volume claims for data retention
- Regular backup recommended

## 🚀 Scaling

### Horizontal Scaling
```bash
# Scale rollup nodes
kubectl scale statefulset op-geth -n rollup --replicas=3
kubectl scale statefulset op-node -n rollup --replicas=3
```

### Vertical Scaling
Update resource requests/limits in the deployment manifests and redeploy.

### Auto-scaling
EKS cluster auto-scaler is enabled by default and will add/remove nodes based on demand.

## 🛠️ Troubleshooting

### Common Issues

#### Pods Stuck in Pending
```bash
# Check node capacity
kubectl describe nodes

# Check events
kubectl get events -n rollup --sort-by='.lastTimestamp'
```

#### Storage Issues
```bash
# Check PVC status
kubectl get pvc -n rollup
kubectl get pvc -n ethereum

# Check storage class
kubectl get storageclass
```

#### Network Connectivity
```bash
# Test internal connectivity
kubectl exec -it <pod-name> -n rollup -- curl http://execution-client.ethereum.svc.cluster.local:8545

# Check service endpoints
kubectl get endpoints -n rollup
```

### Logs
```bash
# View rollup logs
kubectl logs -f statefulset/op-geth -n rollup
kubectl logs -f statefulset/op-node -n rollup

# View Ethereum logs
kubectl logs -f statefulset/execution-client -n ethereum
kubectl logs -f statefulset/beacon-chain -n ethereum
```

## 🗑️ Cleanup

To destroy all infrastructure:

```bash
./scripts/destroy.sh
```

**⚠️ Warning**: This will permanently delete all data and resources!

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section
2. Review Kubernetes and AWS EKS documentation
3. Open an issue with detailed logs and configuration

## 🔗 References

- [Optimism Docs](https://docs.optimism.io/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Ethereum Node Setup](https://ethereum.org/en/developers/docs/nodes-and-clients/)
- [Kubernetes Production Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)

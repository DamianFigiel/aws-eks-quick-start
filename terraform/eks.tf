module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    vpc-cni = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    aws-ebs-csi-driver = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn
    }
  }

  eks_managed_node_groups = {
    rollup-nodes = {
      name = "rollup-nodes"

      instance_types = var.node_group_instance_types
      capacity_type  = "SPOT"

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      ami_type                   = "AL2023_x86_64_STANDARD"
      platform                   = "linux"
      force_update_version       = false
      use_custom_launch_template = false

      disk_size = 100
      disk_type = "gp3"

      create_iam_role          = true
      iam_role_name            = "EKS-rollup-nodes"
      iam_role_use_name_prefix = false
      iam_role_description     = "EKS managed node group role for rollup nodes"
      iam_role_tags = {
        Purpose = "Protector of the kubelet"
      }

      iam_role_additional_policies = {
        AmazonEKSWorkerNodePolicy          = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
        AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonEBSCSIDriverPolicy           = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
        EC2VolumeOperations                = aws_iam_policy.ec2_volume_operations.arn
      }

      labels = {
        Environment = "production"
        NodeGroup   = "rollup-nodes"
      }

      taints = {
      }

      tags = {
        ExtraTag = "rollup-nodes"
      }
    }

    ethereum-nodes = {
      name = "ethereum-nodes"

      instance_types = ["m6i.2xlarge", "m5.2xlarge"]
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = 5
      desired_size = 2

      ami_type                   = "AL2023_x86_64_STANDARD"
      platform                   = "linux"
      force_update_version       = false
      use_custom_launch_template = false

      disk_size = 500
      disk_type = "gp3"

      create_iam_role          = true
      iam_role_name            = "EKS-ethereum-nodes"
      iam_role_use_name_prefix = false
      iam_role_description     = "EKS managed node group role for ethereum nodes"

      iam_role_additional_policies = {
        AmazonEKSWorkerNodePolicy          = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
        AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonEBSCSIDriverPolicy           = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
        EC2VolumeOperations                = aws_iam_policy.ec2_volume_operations.arn
      }

      labels = {
        Environment  = "production"
        NodeGroup    = "ethereum-nodes"
        WorkloadType = "ethereum"
      }

      taints = {
        ethereum = {
          key    = "ethereum"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      tags = {
        ExtraTag = "ethereum-nodes"
      }
    }
  }

  # Fix the for_each error by disabling cluster primary security group tags
  create_cluster_primary_security_group_tags = false

  tags = local.tags
}
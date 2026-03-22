module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  cluster_addons = merge(
    {
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
    },
    var.enable_cloudwatch_observability ? {
      amazon-cloudwatch-observability = {
        most_recent                 = true
        resolve_conflicts_on_create = "OVERWRITE"
        resolve_conflicts_on_update = "OVERWRITE"
        service_account_role_arn    = aws_iam_role.cloudwatch_observability.arn
      }
    } : {}
  )

  eks_managed_node_groups = {
    general = {
      name = "general"

      instance_types = var.node_group_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      ami_type                   = "AL2023_x86_64_STANDARD"
      platform                   = "linux"
      force_update_version       = false
      use_custom_launch_template = false

      disk_size = var.node_group_disk_size
      disk_type = "gp3"

      create_iam_role          = true
      iam_role_name            = "${local.name}-general-nodes"
      iam_role_use_name_prefix = false
      iam_role_description     = "EKS managed node group role"

      iam_role_additional_policies = {
        AmazonEKSWorkerNodePolicy          = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
        AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonEBSCSIDriverPolicy           = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
        CloudWatchAgentServerPolicy        = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        EC2VolumeOperations                = aws_iam_policy.ec2_volume_operations.arn
      }

      labels = {
        Environment = "production"
        NodeGroup   = "general"
      }

      tags = {
        NodeGroup = "general"
      }
    }
  }

  fargate_profiles = var.enable_fargate ? {
    for ns in var.fargate_namespaces : ns => {
      name = ns
      selectors = [
        { namespace = ns }
      ]
    }
  } : {}

  create_cluster_primary_security_group_tags = false

  tags = local.tags
}
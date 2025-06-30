# Create an EKS access entry for the current user
resource "aws_eks_access_entry" "current_user" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
  
  depends_on = [module.eks]
}

# Associate the AmazonEKSAdminPolicy with the current user
resource "aws_eks_access_policy_association" "current_user_admin" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
  principal_arn = aws_eks_access_entry.current_user.principal_arn

  access_scope {
    type = "cluster"
  }
}

# Associate the AmazonEKSClusterAdminPolicy with the current user
resource "aws_eks_access_policy_association" "current_user_cluster_admin" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.current_user.principal_arn

  access_scope {
    type = "cluster"
  }
}

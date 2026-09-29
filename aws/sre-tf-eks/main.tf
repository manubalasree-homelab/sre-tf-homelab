module "ebs_csi_pod_identity" {
  source = "../../terraform-aws-eks-pod-identity"

  name                      = "${var.cluster_name}-ebs-csi"
  attach_aws_ebs_csi_policy = true

  tags = var.tags
}

module "eks" {
  source = "../../terraform-aws-eks"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.public_access_cidrs

  # Access is explicit: only var.admin_principal_arns, never the CI creator.
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    for arn in var.admin_principal_arns : arn => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Older charts still expect IRSA, so keep the OIDC provider on.
  enable_irsa = true

  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    for name, ng in var.node_groups : name => {
      instance_types      = ng.instance_types
      capacity_type       = ng.capacity_type
      ami_type            = ng.ami_type
      min_size            = ng.min_size
      max_size            = ng.max_size
      desired_size        = ng.desired_size
      kubernetes_version  = coalesce(ng.kubernetes_version, var.kubernetes_version)
      ami_release_version = ng.ami_release_version
    }
  }

  tags = var.tags
}

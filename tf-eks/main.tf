provider "aws" {
  region = var.region
}

module "eks" {
  source = "git::https://github.com/manubalasree-homelab/sre-tf-eks.git?ref=v0.1.0"

  cluster_name         = var.cluster_name
  kubernetes_version   = var.kubernetes_version
  vpc_id               = var.vpc_id
  subnet_ids           = var.subnet_ids
  node_groups          = var.node_groups
  admin_principal_arns = var.admin_principal_arns
  public_access_cidrs  = var.public_access_cidrs
  tags                 = var.tags
}

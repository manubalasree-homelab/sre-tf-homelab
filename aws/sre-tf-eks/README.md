# sre-tf-eks

Thin wrapper around the mirrored `../../terraform-aws-eks` (upstream [`terraform-aws-modules/eks/aws`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest))
(pinned by tag in `mirrors.conf`; see ADR-0003 and ADR-0004). A reusable module: no backend, no provider
config. Root configs live in other repos.

```hcl
module "eks" {
  source = "git::https://github.com/manubalasree-homelab/sre-tf-homelab.git//aws/sre-tf-eks?ref=refs/tags/v1.6.1"

  cluster_name        = "aws-lab-us-east-1-01"
  kubernetes_version  = "1.33"
  vpc_id              = var.vpc_id
  subnet_ids          = var.private_subnet_ids
  public_access_cidrs = ["203.0.113.7/32"]
  admin_principal_arns = ["arn:aws:iam::111122223333:user/homelab-admin"]

  node_groups = {
    default = {} # Spot t3.medium, 1-3 nodes
  }
}
```

Includes EKS-native addons only (`vpc-cni`, `coredns`, `kube-proxy`,
`eks-pod-identity-agent`, `aws-ebs-csi-driver` via Pod Identity); everything
else is installed by ArgoCD. Access is via access entries only.
Node groups accept `kubernetes_version` and `ami_release_version` so nodes
can lag the control plane.

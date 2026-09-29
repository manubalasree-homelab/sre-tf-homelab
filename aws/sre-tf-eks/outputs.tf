output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "node_iam_role_arns" {
  description = "Node IAM role ARN per managed node group."
  value       = { for name, ng in module.eks.eks_managed_node_groups : name => ng.iam_role_arn }
}

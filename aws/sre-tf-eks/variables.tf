variable "cluster_name" {
  description = "Finished cluster name, `<provider>-<env>-<region>-<nn>` (e.g. `aws-lab-us-east-1-01`)."
  type        = string

  validation {
    condition     = can(regex("^aws-[a-z0-9]+(-[a-z]+){1,2}-[0-9]+-[0-9]{2}$", var.cluster_name))
    error_message = "cluster_name must match <provider>-<env>-<region>-<nn>, e.g. aws-lab-us-east-1-01."
  }
}

variable "kubernetes_version" {
  description = "EKS control plane version (e.g. \"1.33\"). No default: the var files make this choice deliberately."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster runs in."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control plane ENIs and the node groups."
  type        = list(string)
}

variable "node_groups" {
  description = "EKS managed node groups, keyed by name. kubernetes_version and ami_release_version default to the control plane's / latest, and can be set to let nodes lag the control plane."
  type = map(object({
    instance_types      = optional(list(string), ["t3.medium"])
    capacity_type       = optional(string, "SPOT")
    ami_type            = optional(string, "AL2023_x86_64_STANDARD")
    min_size            = optional(number, 1)
    max_size            = optional(number, 3)
    desired_size        = optional(number, 2)
    kubernetes_version  = optional(string)
    ami_release_version = optional(string)
  }))
}

variable "admin_principal_arns" {
  description = "IAM principals granted cluster admin through EKS access entries. The applying CI role is not made admin implicitly."
  type        = list(string)
  default     = []
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. No default: the exposure is a deliberate choice."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

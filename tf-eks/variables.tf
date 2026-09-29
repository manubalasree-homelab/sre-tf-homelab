# Values come from homelab-tf-account-vars via the var-file cascade.

variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "node_groups" {
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
  type    = list(string)
  default = []
}

variable "public_access_cidrs" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "account" {
  description = "Example scaling dimension: which account this scope represents"
  type        = string
  default     = "shared"
}

variable "environment" {
  description = "Example scaling dimension: which environment this scope represents"
  type        = string
  default     = "shared"
}

variable "region" {
  description = "Example scaling dimension: which region this scope represents"
  type        = string
  default     = "shared"
}

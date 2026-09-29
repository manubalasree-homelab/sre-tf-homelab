terraform {
  required_version = ">= 1.6"

  # Partial config: bucket, key, region and dynamodb_table arrive as
  # -backend-config lines from the deploy workflow.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

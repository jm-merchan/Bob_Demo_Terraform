provider "aws" {
  region = var.aws_region

  # Dynamic credentials via HCP Terraform:
  # TFC_AWS_PROVIDER_AUTH and TFC_AWS_RUN_ROLE_ARN are injected by the global
  # aws-dynamic-provider-credentials varset — no static keys, no assume_role {} needed.

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}

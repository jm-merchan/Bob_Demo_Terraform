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

# Kubernetes provider — connects to the EKS cluster using coordinates from eks-infra-vcs
# remote state (via locals.tf). exec block used over data.aws_eks_cluster_auth: tokens
# from aws_eks_cluster_auth expire after 15 minutes; exec block re-invokes
# aws eks get-token before each Kubernetes API call (safe for long-running applies).
# api_version "client.authentication.k8s.io/v1" is mandatory — v1beta1 was removed
# in Kubernetes 1.29; the live cluster runs 1.33.
# Two-state boundary honoured: provider reads from settled remote state, not
# same-workspace computed resources (design §2 architectural decision).
provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = local.cluster_ca_certificate

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", local.cluster_name,
      "--region", var.aws_region,
    ]
  }
}

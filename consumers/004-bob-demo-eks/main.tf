# EKS cluster — composed from the jose-merchan/eks-bob/aws PMR module.
# VPC is auto-created by the module when vpc_id is not provided (vpc_id = null by default).
module "eks_cluster" {
  source  = "app.terraform.io/jose-merchan/eks-bob/aws"
  version = "~> 0.1"

  # Required inputs
  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  environment        = var.environment

  # Node group
  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size

  # [SECURITY OVERRIDE] — public endpoint enabled for sandbox operator access.
  # Operators without private VPC connectivity need public API server access.
  # Private endpoint (endpoint_private_access = true) remains hardcoded active in the module.
  # See consumer-design.md §2 (Architectural Decisions) and §4 (Security Controls).
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Security defaults honoured (module defaults — not overridden):
  #   kms_key_enabled   = true   → CMK envelope encryption for K8s secrets (EKS.3)
  #   cluster_log_types = all 5  → control-plane logging to CloudWatch (EKS.8)
  #   enable_irsa       = true   → OIDC provider for pod-level IAM roles
}

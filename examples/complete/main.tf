# Example: Complete EKS Cluster
#
# Demonstrates all available features:
#   - Custom VPC CIDR and AZs
#   - Public EKS endpoint restricted to an IP range
#   - KMS customer-managed key for secrets encryption
#   - All 5 control plane log types + 365-day retention
#   - HA NAT Gateway (one per AZ)
#   - IRSA (OIDC provider for pod IAM roles)
#   - SPOT nodes with multiple instance types for cost optimisation
#   - Custom tags for cost allocation

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "eks_cluster" {
  source  = "app.terraform.io/jose-merchan/eks-cluster-bob/aws"
  version = "0.0.1"

  cluster_name       = var.cluster_name
  kubernetes_version = "1.32"
  environment        = "prod"

  # VPC configuration — create with HA NAT
  vpc_cidr               = "10.100.0.0/16"
  availability_zones     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs    = ["10.100.101.0/24", "10.100.102.0/24", "10.100.103.0/24"]
  private_subnet_cidrs   = ["10.100.1.0/24", "10.100.2.0/24", "10.100.3.0/24"]
  one_nat_gateway_per_az = true
  enable_vpc_flow_logs   = true

  # Security — public endpoint with CIDR restriction
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["10.0.0.0/8"]
  kms_key_enabled                      = true

  # Logging — all types, 1-year retention
  cluster_log_types             = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_log_retention_in_days = 365

  # IRSA and authentication
  enable_irsa         = true
  authentication_mode = "API_AND_CONFIG_MAP"

  # Node group — SPOT with mixed instance types; Cluster Autoscaler manages desired_size
  node_instance_types = ["m5.large", "m5a.large", "m5d.large"]
  node_capacity_type  = "SPOT"
  node_min_size       = 2
  node_max_size       = 10
  node_desired_size   = 3
  node_disk_size      = 50

  tags = {
    Owner      = "platform-team"
    CostCenter = "engineering"
    Env        = "prod"
  }
}

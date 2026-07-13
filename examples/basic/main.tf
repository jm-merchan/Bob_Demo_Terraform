# Example: Basic EKS Cluster
#
# Demonstrates minimum viable usage. Creates a new VPC, deploys an EKS cluster
# with all secure defaults (private endpoint, KMS encryption, full audit logging),
# and a single managed node group.

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
  environment        = "dev"

  node_instance_types = ["t3.medium"]
  node_min_size       = 1
  node_max_size       = 3
  node_desired_size   = 2

  tags = {
    Owner = "platform-team"
  }
}

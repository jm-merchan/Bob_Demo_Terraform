# Example: Basic — deploy backend with secure defaults
#
# Demonstrates minimum viable usage: deploys de.icr.io/san-clients/backend:latest
# into an existing Kubernetes namespace using a ClusterIP service (no external exposure).
# Registry credentials must be supplied as environment variables or tfvars — never
# hardcoded in configuration files.
#
# Prerequisites:
#   - A running EKS cluster (e.g. provisioned by the eks-infra module)
#   - A kubeconfig or direct cluster credentials
#   - The target namespace must already exist
#
# Provider authentication pattern for EKS:
#   Use the exec block with api_version = "client.authentication.k8s.io/v1"
#   (v1beta1 was removed in Kubernetes 1.29 / EKS 1.32+).

terraform {
  required_version = ">= 1.14"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.2.1"
    }
  }
}

# Configure the kubernetes provider using EKS exec-based authentication.
# Cluster details should come from a data source or remote state — never hardcoded.
provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_cert)

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
  }
}

# Deploy the backend application with all secure defaults.
# service_type defaults to "ClusterIP" — internal access only.
module "backend" {
  source = "../../"

  app_name  = var.app_name
  namespace = var.namespace
  image     = var.image
  replicas  = var.replicas

  # Registry credentials — passed as sensitive variables, never hardcoded
  registry_server   = var.registry_server
  registry_username = var.registry_username
  registry_password = var.registry_password
}

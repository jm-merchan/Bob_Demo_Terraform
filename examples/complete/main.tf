# Example: Complete — deploy backend with public LoadBalancer on EKS
#
# Demonstrates all available features:
#   - Public LoadBalancer service type (external access via AWS ELB)
#   - Custom resource requests/limits
#   - Configurable liveness and readiness probe paths
#   - Credential rotation counter (registry_secret_revision)
#   - All optional inputs explicitly set
#
# Target cluster: eks-infra-dev (eu-central-1)
# Cluster details sourced from eks-infra-vcs HCP Terraform workspace outputs.
# Registry credentials supplied via workspace variables or TF_VAR_* env vars.
#
# ⚠️  Security note: service_type = "LoadBalancer" provisions a public AWS ELB.
#     Ensure appropriate Security Groups and Network Policies restrict access.
#     Consider placing a WAF or Ingress with TLS in front for production traffic.

terraform {
  required_version = ">= 1.14"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.2.1"
    }
  }
}

# Kubernetes provider — authenticated against EKS using aws-cli exec plugin.
# api_version MUST be "client.authentication.k8s.io/v1" (v1beta1 removed in EKS 1.32+).
provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_cert)

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
  }
}

# Deploy the backend application with a public LoadBalancer and custom resource sizing.
module "backend" {
  source = "../../"

  # Identity
  app_name  = var.app_name
  namespace = var.namespace
  image     = var.image
  replicas  = var.replicas

  # Network — expose publicly via AWS ELB (NLB provisioned by EKS cloud-controller-manager)
  service_type   = "LoadBalancer"
  container_port = var.container_port

  # Resource sizing — tune for production load
  cpu_request    = var.cpu_request
  memory_request = var.memory_request
  cpu_limit      = var.cpu_limit
  memory_limit   = var.memory_limit

  # Health probes — app exposes /health/live and /health/ready
  enable_liveness_probe  = true
  enable_readiness_probe = true
  liveness_path          = var.liveness_path
  readiness_path         = var.readiness_path

  # Registry credentials — sensitive; passed via tfvars or TF_VAR_* env vars
  registry_server          = var.registry_server
  registry_username        = var.registry_username
  registry_password        = var.registry_password
  registry_secret_revision = var.registry_secret_revision
}

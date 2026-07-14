variable "cluster_endpoint" {
  description = "EKS cluster API server endpoint URL."
  type        = string
  # Value: https://3125B0917588D1171379955B63B61EA2.gr7.eu-central-1.eks.amazonaws.com
  # Source: eks-infra-vcs workspace output cluster_endpoint
}

variable "cluster_ca_cert" {
  description = "Base64-encoded certificate authority data for the EKS cluster."
  type        = string
  sensitive   = true
  # Source: eks-infra-vcs workspace output cluster_certificate_authority_data
}

variable "cluster_name" {
  description = "EKS cluster name — used by aws eks get-token for authentication."
  type        = string
  default     = "eks-infra-dev"
  # Source: eks-infra-vcs workspace output cluster_name
}

variable "aws_region" {
  description = "AWS region where the EKS cluster resides."
  type        = string
  default     = "eu-central-1"
}

variable "app_name" {
  description = "Application name — used for resource naming and Kubernetes labels."
  type        = string
  default     = "backend"
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into. Must already exist in the cluster."
  type        = string
  default     = "default"
}

variable "image" {
  description = "Full OCI image reference including registry, repository and tag."
  type        = string
  default     = "de.icr.io/san-clients/backend:latest"
}

variable "replicas" {
  description = "Number of pod replicas."
  type        = number
  default     = 2
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "cpu_request" {
  description = "CPU resource request per pod."
  type        = string
  default     = "250m"
}

variable "memory_request" {
  description = "Memory resource request per pod."
  type        = string
  default     = "256Mi"
}

variable "cpu_limit" {
  description = "CPU resource limit per pod."
  type        = string
  default     = "500m"
}

variable "memory_limit" {
  description = "Memory resource limit per pod."
  type        = string
  default     = "512Mi"
}

variable "liveness_path" {
  description = "HTTP GET path for the liveness probe."
  type        = string
  default     = "/health/live"
}

variable "readiness_path" {
  description = "HTTP GET path for the readiness probe."
  type        = string
  default     = "/health/ready"
}

variable "registry_server" {
  description = "Private container registry hostname (e.g. de.icr.io for IBM ICR)."
  type        = string
  sensitive   = true
}

variable "registry_username" {
  description = "Registry authentication username (iamapikey for IBM ICR with API key auth)."
  type        = string
  sensitive   = true
}

variable "registry_password" {
  description = "Registry authentication password or IBM IAM API key."
  type        = string
  sensitive   = true
}

variable "registry_secret_revision" {
  description = "Revision counter. Increment to trigger an in-place credential rotation."
  type        = number
  default     = 1
}

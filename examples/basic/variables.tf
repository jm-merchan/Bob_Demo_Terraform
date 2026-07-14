variable "cluster_endpoint" {
  description = "EKS cluster API server endpoint URL."
  type        = string
}

variable "cluster_ca_cert" {
  description = "Base64-encoded certificate authority data for the EKS cluster."
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "EKS cluster name — used by aws eks get-token for authentication."
  type        = string
}

variable "aws_region" {
  description = "AWS region where the EKS cluster resides."
  type        = string
  default     = "eu-central-1"
}

variable "app_name" {
  description = "Application name — used for resource naming and labels."
  type        = string
  default     = "backend"
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into. Must already exist."
  type        = string
  default     = "default"
}

variable "image" {
  description = "Full OCI image reference."
  type        = string
  default     = "de.icr.io/san-clients/backend:latest"
}

variable "replicas" {
  description = "Number of pod replicas."
  type        = number
  default     = 1
}

variable "registry_server" {
  description = "Private registry hostname (e.g. de.icr.io)."
  type        = string
  sensitive   = true
}

variable "registry_username" {
  description = "Registry authentication username (e.g. iamapikey for IBM ICR)."
  type        = string
  sensitive   = true
}

variable "registry_password" {
  description = "Registry authentication password or API key."
  type        = string
  sensitive   = true
}

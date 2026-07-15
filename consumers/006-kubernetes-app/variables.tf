variable "aws_region" {
  type        = string
  default     = "eu-central-1"
  description = "AWS region to deploy into. Must match the region of the eks-infra-vcs workspace. Used in provider block (cannot reference data sources in provider config)."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region, e.g. eu-central-1."
  }
}

variable "project_name" {
  type        = string
  default     = "k8s-app-demo"
  description = "Project name applied to default_tags Project key and used in workspace labelling."
}

variable "environment" {
  type        = string
  default     = "sandbox"
  description = "Deployment environment identifier applied to all resource tags."

  validation {
    condition     = contains(["dev", "staging", "prod", "sandbox"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, sandbox."
  }
}

variable "owner" {
  type        = string
  default     = "platform-team"
  description = "Owner value for default_tags Owner key; used for cost allocation reporting."
}

variable "infra_workspace" {
  type        = string
  default     = "eks-infra-vcs"
  description = "Name of the HCP Terraform workspace that exposes EKS cluster outputs via remote state. Follows the eks-vault-vcs org pattern."

  validation {
    condition     = length(var.infra_workspace) > 0
    error_message = "infra_workspace must not be empty."
  }
}

variable "namespace" {
  type        = string
  default     = "bob-demo-app"
  description = "Kubernetes namespace to create and deploy the application into. Must be a valid RFC 1123 DNS label."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid RFC 1123 DNS label (lowercase alphanumeric and hyphens, no leading/trailing hyphens)."
  }
}

variable "app_name" {
  type        = string
  default     = "backend"
  description = "Application name. Used as base for all Kubernetes resource names and pod-selector labels. RFC 1123 DNS label."

  validation {
    condition     = length(var.app_name) >= 1 && length(var.app_name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.app_name))
    error_message = "app_name must be 1–63 characters, lowercase alphanumeric with internal hyphens, no leading/trailing hyphens (RFC 1123)."
  }
}

variable "image" {
  type        = string
  default     = "de.icr.io/san-clients/backend:latest"
  description = "Full OCI image reference including registry and tag."

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty."
  }
}

variable "replicas" {
  type        = number
  default     = 2
  description = "Number of pod replicas. Must be 1–100."

  validation {
    condition     = var.replicas >= 1 && var.replicas <= 100
    error_message = "replicas must be between 1 and 100 (inclusive)."
  }
}

variable "registry_server" {
  type        = string
  description = "Hostname of the private container registry (e.g., de.icr.io). Set as workspace variable."

  validation {
    condition     = length(var.registry_server) > 0
    error_message = "registry_server must not be empty."
  }
}

variable "registry_username" {
  type        = string
  description = "Registry authentication username (e.g., iamapikey for IBM ICR). Set as workspace variable."

  validation {
    condition     = length(var.registry_username) > 0
    error_message = "registry_username must not be empty."
  }
}

variable "registry_password" {
  type        = string
  sensitive   = true
  description = "Registry authentication password or API key. Written via module data_wo — never stored in state. Set as sensitive workspace variable."

  validation {
    condition     = length(var.registry_password) > 0
    error_message = "registry_password must not be empty."
  }
}

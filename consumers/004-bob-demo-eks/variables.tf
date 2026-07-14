variable "aws_region" {
  type        = string
  default     = "eu-west-1"
  description = "AWS region to deploy into. Default eu-west-1; also controlled by workspace env var AWS_REGION."
}

variable "project_name" {
  type        = string
  default     = "bob-demo-eks"
  description = "Project name applied to default_tags Project key and used in workspace labelling."
}

variable "owner" {
  type        = string
  default     = "platform-team"
  description = "Owner value for default_tags Owner key; used for cost allocation reporting."
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Also used as the VPC name and node group name prefix inside the module."

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 100 && can(regex("^[a-zA-Z0-9_-]+$", var.cluster_name))
    error_message = "cluster_name must be 1–100 characters and match ^[a-zA-Z0-9_-]+$."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = "1.32"
  description = "Kubernetes control-plane version. No v prefix (e.g. \"1.32\")."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must match ^[0-9]+\\.[0-9]+$ (e.g. \"1.32\", no v prefix)."
  }
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

variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "EC2 instance types for the managed node group."

  validation {
    condition     = length(var.node_instance_types) >= 1
    error_message = "node_instance_types must contain at least 1 element."
  }
}

variable "node_min_size" {
  type        = number
  default     = 1
  description = "Minimum number of nodes in the managed node group."

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size must be >= 1."
  }
}

variable "node_max_size" {
  type        = number
  default     = 3
  description = "Maximum number of nodes in the managed node group."

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size must be >= 1."
  }
}

variable "node_desired_size" {
  type        = number
  default     = 2
  description = "Desired node count at cluster creation time."

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be >= 1."
  }
}

# [SECURITY OVERRIDE] Public endpoint CIDRs — default is open (0.0.0.0/0) to allow operator
# kubectl access from locations without private VPC connectivity (sandbox requirement).
# Operators SHOULD restrict this to known IPs in non-sandbox environments.
# Justification: design.md Section 2 "Public endpoint enabled with CIDR restriction" and Section 4.
variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "[SECURITY OVERRIDE] CIDR blocks allowed to reach the public EKS API endpoint. Default is open; operators SHOULD restrict to known IPs in non-sandbox environments."
}

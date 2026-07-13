variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster. Must be 1-100 characters, alphanumeric, hyphens, or underscores."

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 100
    error_message = "cluster_name must be between 1 and 100 characters."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.cluster_name))
    error_message = "cluster_name may only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster control plane (e.g. \"1.32\"). Must be MAJOR.MINOR format."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be in MAJOR.MINOR format (e.g. \"1.32\"). Do not include a 'v' prefix."
  }
}

variable "environment" {
  type        = string
  description = "Environment identifier applied to all resource tags (e.g. \"dev\", \"staging\", \"prod\", \"sandbox\")."

  validation {
    condition     = contains(["dev", "staging", "prod", "sandbox"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, sandbox."
  }
}

variable "node_instance_types" {
  type        = list(string)
  description = "List of EC2 instance types for the managed node group (e.g. [\"t3.medium\"])."

  validation {
    condition     = length(var.node_instance_types) >= 1
    error_message = "node_instance_types must contain at least one instance type."
  }
}

variable "node_min_size" {
  type        = number
  description = "Minimum number of worker nodes in the managed node group."

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size must be at least 1."
  }
}

variable "node_max_size" {
  type        = number
  description = "Maximum number of worker nodes in the managed node group. Must be >= node_min_size."

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size must be at least 1."
  }
}

variable "node_desired_size" {
  type        = number
  description = "Desired number of worker nodes at cluster creation. Must be between node_min_size and node_max_size."

  validation {
    condition     = var.node_desired_size >= 1
    error_message = "node_desired_size must be at least 1."
  }
}

# --- VPC inputs (optional) ---

variable "vpc_id" {
  type        = string
  description = "ID of an existing VPC to use. When null or empty string, a new VPC is created automatically."
  default     = null
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs of existing private subnets for worker nodes. Required when vpc_id is provided; ignored when creating a new VPC."
  default     = []
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "IDs of existing public subnets for load balancer ENIs. Required when vpc_id is provided; ignored when creating a new VPC."
  default     = []
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the new VPC. Only used when vpc_id is not provided."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR notation (e.g. \"10.0.0.0/16\")."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones for subnet creation. Auto-discovered from AWS when empty. Minimum two required by EKS."
  default     = []

  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) >= 2
    error_message = "availability_zones must be empty (auto-discover) or contain at least 2 zones."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets, one per availability zone. Only used when creating a new VPC."
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets, one per availability zone. /20 or larger recommended for node and pod IP allocation."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "one_nat_gateway_per_az" {
  type        = bool
  description = "When true, one NAT gateway is created per AZ (high availability). When false, a single shared NAT gateway is used (cost saving)."
  default     = false
}

variable "enable_vpc_flow_logs" {
  type        = bool
  description = "Enable VPC Flow Logs for the created VPC. Recommended for production environments."
  default     = false
}

# --- Security inputs ---

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Whether the EKS API server endpoint is reachable from the public internet. Defaults to false (Security Hub EKS.1)."
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the public endpoint. Only applies when cluster_endpoint_public_access = true. Should be restricted to known CIDRs in production."
  default     = ["0.0.0.0/0"]
}

variable "kms_key_enabled" {
  type        = bool
  description = "Create and attach a customer-managed KMS key for Kubernetes secrets envelope encryption. Defaults to true (Security Hub EKS.3)."
  default     = true
}

variable "cluster_log_types" {
  type        = list(string)
  description = "Control plane log types to send to CloudWatch. Defaults to all five types (Security Hub EKS.8)."
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_in_days" {
  type        = number
  description = "CloudWatch log group retention in days. Must be a valid CloudWatch retention value."
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cluster_log_retention_in_days)
    error_message = "cluster_log_retention_in_days must be a valid CloudWatch retention value: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, or 3653."
  }
}

variable "enable_irsa" {
  type        = bool
  description = "Enable the OIDC provider for IAM Roles for Service Accounts (IRSA). Defaults to true."
  default     = true
}

variable "authentication_mode" {
  type        = string
  description = "EKS cluster authentication mode. API_AND_CONFIG_MAP supports both EKS access entries and the legacy aws-auth ConfigMap."
  default     = "API_AND_CONFIG_MAP"

  validation {
    condition     = contains(["CONFIG_MAP", "API", "API_AND_CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be one of: CONFIG_MAP, API, API_AND_CONFIG_MAP."
  }
}

# --- Node group inputs ---

variable "node_capacity_type" {
  type        = string
  description = "Node group capacity type. ON_DEMAND provides consistent availability; SPOT reduces cost with interruption risk."
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be one of: ON_DEMAND, SPOT."
  }
}

variable "node_disk_size" {
  type        = number
  description = "EBS root volume size in GiB for worker nodes."
  default     = 20

  validation {
    condition     = var.node_disk_size >= 20
    error_message = "node_disk_size must be at least 20 GiB."
  }
}

# --- Tagging ---

variable "tags" {
  type        = map(string)
  description = "Additional tags merged onto all taggable resources. Consumer-provided tags take precedence over module defaults."
  default     = {}
}

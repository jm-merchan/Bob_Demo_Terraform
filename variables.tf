variable "app_name" {
  type        = string
  description = "Application name. Used as the base for all resource names, pod-selector labels, and the app.kubernetes.io/name label. Must be a valid RFC 1123 DNS label."

  validation {
    condition     = length(var.app_name) >= 1 && length(var.app_name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.app_name))
    error_message = "app_name must be a valid RFC 1123 DNS label: lowercase alphanumeric and hyphens only, 1-63 characters, must start and end with alphanumeric."
  }
}

variable "namespace" {
  type        = string
  description = "Target Kubernetes namespace. Must exist before apply. Must be a valid RFC 1123 DNS label (lowercase alphanumeric and hyphens, max 63 chars, start and end with alphanumeric)."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid RFC 1123 DNS label: lowercase alphanumeric and hyphens only, max 63 characters, must start and end with alphanumeric."
  }
}

variable "image" {
  type        = string
  description = "Full OCI image reference including registry and tag (e.g., de.icr.io/san-clients/backend:latest). Must not be empty."

  validation {
    condition     = length(var.image) > 0
    error_message = "image must not be empty. Provide a full OCI image reference including registry and tag."
  }
}

variable "replicas" {
  type        = number
  description = "Number of pod replicas to run. Must be between 1 and 100 inclusive. Passed to the provider as a string via tostring()."

  validation {
    condition     = var.replicas >= 1 && var.replicas <= 100
    error_message = "Replica count must be between 1 and 100 inclusive."
  }
}

variable "registry_server" {
  type        = string
  sensitive   = true
  description = "Hostname of the private container registry (e.g., de.icr.io). Used to construct the .dockerconfigjson auth payload."

  validation {
    condition     = length(var.registry_server) > 0
    error_message = "registry_server must not be empty."
  }
}

variable "registry_username" {
  type        = string
  sensitive   = true
  description = "Username for registry authentication (e.g., iamapikey for IBM ICR)."

  validation {
    condition     = length(var.registry_username) > 0
    error_message = "registry_username must not be empty."
  }
}

variable "registry_password" {
  type        = string
  sensitive   = true
  description = "Password or API key for registry authentication. Written via data_wo — never stored in state."

  validation {
    condition     = length(var.registry_password) > 0
    error_message = "registry_password must not be empty."
  }
}

variable "registry_secret_revision" {
  type        = number
  description = "Revision counter for the registry pull secret. Increment this value to trigger a credential rotation (replaces data_wo payload in-place)."
  default     = 1

  validation {
    condition     = var.registry_secret_revision >= 1
    error_message = "registry_secret_revision must be >= 1."
  }
}

variable "container_port" {
  type        = number
  description = "Container port the application listens on. Used for the pod port declaration and health probe HTTP GET target."
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535 inclusive."
  }
}

variable "service_type" {
  type        = string
  description = "Kubernetes service type. Defaults to ClusterIP (no external exposure). Use LoadBalancer only with appropriate cloud annotations."
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.service_type)
    error_message = "service_type must be one of: ClusterIP, NodePort, LoadBalancer."
  }
}

variable "service_annotations" {
  type        = map(string)
  description = "Annotations to apply to the Kubernetes service metadata. Use to pass cloud-provider-specific annotations (e.g., NLB: {\"service.beta.kubernetes.io/aws-load-balancer-type\" = \"nlb\"}). Defaults to empty map (no annotations)."
  default     = {}
}

variable "cpu_request" {
  type        = string
  description = "CPU resource request per container pod. Kubernetes quantity string (e.g., \"250m\", \"0.25\")."
  default     = "250m"

  validation {
    condition     = can(regex("^[0-9]+(m|[.][0-9]+)?$", var.cpu_request))
    error_message = "cpu_request must be a valid Kubernetes CPU quantity string (e.g., \"250m\", \"0.25\")."
  }
}

variable "memory_request" {
  type        = string
  description = "Memory resource request per container pod. Kubernetes quantity string (e.g., \"256Mi\", \"512M\")."
  default     = "256Mi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|M|G|Ki|K|Ti|T)?$", var.memory_request))
    error_message = "memory_request must be a valid Kubernetes memory quantity string (e.g., \"256Mi\", \"1Gi\")."
  }
}

variable "cpu_limit" {
  type        = string
  description = "CPU resource limit per container pod. Must be >= cpu_request. Kubernetes quantity string."
  default     = "500m"

  validation {
    condition     = can(regex("^[0-9]+(m|[.][0-9]+)?$", var.cpu_limit))
    error_message = "cpu_limit must be a valid Kubernetes CPU quantity string (e.g., \"500m\", \"1.0\")."
  }
}

variable "memory_limit" {
  type        = string
  description = "Memory resource limit per container pod. Must be >= memory_request. Kubernetes quantity string."
  default     = "512Mi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|M|G|Ki|K|Ti|T)?$", var.memory_limit))
    error_message = "memory_limit must be a valid Kubernetes memory quantity string (e.g., \"512Mi\", \"1Gi\")."
  }
}

variable "liveness_path" {
  type        = string
  description = "HTTP GET path for the liveness probe. Must start with /. Liveness checks MUST NOT call external dependencies."
  default     = "/health/live"

  validation {
    condition     = can(regex("^/", var.liveness_path))
    error_message = "liveness_path must start with /."
  }
}

variable "readiness_path" {
  type        = string
  description = "HTTP GET path for the readiness probe. Must start with /. May check upstream dependency health."
  default     = "/health/ready"

  validation {
    condition     = can(regex("^/", var.readiness_path))
    error_message = "readiness_path must start with /."
  }
}

variable "enable_liveness_probe" {
  type        = bool
  description = "Enable or disable the container liveness probe. When false, the liveness probe block is omitted entirely."
  default     = true
}

variable "enable_readiness_probe" {
  type        = bool
  description = "Enable or disable the container readiness probe. When false, the readiness probe block is omitted entirely."
  default     = true
}

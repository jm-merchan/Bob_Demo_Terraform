locals {
  # Module default tags merged with consumer tags
  default_tags = {
    Name        = var.cluster_name
    ManagedBy   = "terraform"
    Environment = var.environment
    Application = var.cluster_name
  }

  merged_tags = merge(local.default_tags, var.tags)
}

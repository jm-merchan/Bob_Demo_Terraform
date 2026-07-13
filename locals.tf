locals {
  # Derive VPC creation flag from vpc_id — no separate toggle variable needed
  create_vpc = var.vpc_id == null || var.vpc_id == ""

  # Resolve VPC ID: created or provided
  vpc_id = local.create_vpc ? module.vpc[0].vpc_id : var.vpc_id

  # Resolve subnet IDs: created or provided
  private_subnet_ids = local.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids
  public_subnet_ids  = local.create_vpc ? module.vpc[0].public_subnets : var.public_subnet_ids

  # Combined subnet list for EKS control plane (needs both public and private)
  all_subnet_ids = concat(local.private_subnet_ids, local.public_subnet_ids)

  # Module default tags merged with consumer tags
  default_tags = {
    Name        = var.cluster_name
    ManagedBy   = "terraform"
    Environment = var.environment
    Application = var.cluster_name
  }

  merged_tags = merge(local.default_tags, var.tags)
}

# EKS cluster — delegates to jose-merchan/eks-cluster/aws which composes
# vpc/aws and eks/aws internally and avoids plan-time count issues.
module "eks_cluster" {
  source  = "app.terraform.io/jose-merchan/eks-cluster/aws"
  version = "~> 0.0"

  # Mandatory tags
  # eks-cluster/aws validates environment as dev/staging/prod — map sandbox→dev for internal use
  environment = var.environment == "sandbox" ? "dev" : var.environment
  owner       = lookup(var.tags, "Owner", "platform-team")
  cost_center = lookup(var.tags, "CostCenter", "default")
  project     = var.cluster_name

  # Cluster
  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Endpoint access — public optional (Security Hub EKS.1)
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # IRSA
  enable_irsa = var.enable_irsa

  # Control plane logging (Security Hub EKS.8)
  log_retention_days = var.cluster_log_retention_in_days

  # Node group
  node_groups = {
    default = {
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      disk_size_gb   = var.node_disk_size
    }
  }

  # VPC — create new when vpc_id not provided
  vpc_id               = var.vpc_id
  vpc_cidr             = var.vpc_cidr
  availability_zones   = length(var.availability_zones) > 0 ? var.availability_zones : ["${data.aws_region.current.name}a", "${data.aws_region.current.name}b"]
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  enable_internet_access = true
  single_nat_gateway   = !var.one_nat_gateway_per_az

  additional_tags = local.merged_tags
}

data "aws_region" "current" {}

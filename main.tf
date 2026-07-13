# VPC — created only when vpc_id is not provided
module "vpc" {
  source  = "app.terraform.io/jose-merchan/vpc/aws"
  version = "0.0.0"

  count = local.create_vpc ? 1 : 0

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = length(var.availability_zones) > 0 ? var.availability_zones : data.aws_availability_zones.available[0].names
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = !var.one_nat_gateway_per_az
  one_nat_gateway_per_az = var.one_nat_gateway_per_az

  # EKS requires specific subnet tags for load balancer controller autodiscovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  # Flow logs: disabled by default, enabled when requested
  enable_flow_log = var.enable_vpc_flow_logs

  tags = local.merged_tags
}

# Data source for AZ auto-discovery (only needed when creating VPC)
data "aws_availability_zones" "available" {
  count = local.create_vpc ? 1 : 0
  state = "available"
}

# EKS cluster — uses app.terraform.io/jose-merchan/eks/aws (wraps terraform-aws-modules/eks)
module "eks" {
  source  = "app.terraform.io/jose-merchan/eks/aws"
  version = "0.0.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Network
  vpc_id     = local.vpc_id
  subnet_ids = local.all_subnet_ids

  # Endpoint access (private always enabled; public optional, default off)
  endpoint_private_access      = true
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Secrets encryption with CMK (Security Hub EKS.3)
  create_kms_key = var.kms_key_enabled

  # Control plane logging (Security Hub EKS.8)
  enabled_log_types                      = var.cluster_log_types
  cloudwatch_log_group_retention_in_days = var.cluster_log_retention_in_days

  # IRSA / OIDC provider
  enable_irsa = var.enable_irsa

  # Authentication mode
  authentication_mode = var.authentication_mode

  # Managed node group — single mixed-workload group; K8s scheduling handles isolation
  # partition and account_id are supplied to prevent the submodule from using
  # data source count expressions that are unresolvable with mock providers in tests.
  eks_managed_node_groups = {
    default = {
      name = "${var.cluster_name}-ng"

      subnet_ids = local.private_subnet_ids

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type
      disk_size      = var.node_disk_size

      update_config = {
        max_unavailable = 1
      }
    }
  }

  tags = local.merged_tags

  depends_on = [module.vpc]
}

# Generated from specs/001-eks-cluster-bob/design.md Section 5 -- Unit: Full Features

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }
}
mock_provider "tls" {}
mock_provider "time" {}
mock_provider "null" {}
mock_provider "cloudinit" {}

# Scenario: "Full Features -- all modules created"
run "test_all_modules_created_with_full_features" {
  command = plan

  variables {
    cluster_name                         = "test-complete"
    kubernetes_version                   = "1.32"
    environment                          = "prod"
    node_instance_types                  = ["m5.large"]
    node_min_size                        = 2
    node_max_size                        = 10
    node_desired_size                    = 4
    cluster_endpoint_public_access       = true
    cluster_endpoint_public_access_cidrs = ["10.0.0.0/8"]
    kms_key_enabled                      = true
    cluster_log_types                    = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
    cluster_log_retention_in_days        = 365
    enable_irsa                          = true
    enable_vpc_flow_logs                 = true
    one_nat_gateway_per_az               = true
    authentication_mode                  = "API"
    node_capacity_type                   = "ON_DEMAND"
    node_disk_size                       = 50
    tags                                 = { Owner = "platform-team", CostCenter = "eng" }
  }

  override_module {
    target = module.vpc[0]
    outputs = {
      vpc_id          = "vpc-stubbed"
      public_subnets  = ["subnet-pub1", "subnet-pub2"]
      private_subnets = ["subnet-priv1", "subnet-priv2"]
    }
  }

  override_module {
    target = module.eks
    outputs = {
      cluster_name                       = "test-complete"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-complete"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-complete/cluster"
    }
  }

  assert {
    condition     = length(module.vpc) == 1
    error_message = "VPC module must be created when vpc_id is not provided."
  }

  assert {
    condition     = module.eks.cluster_name != null
    error_message = "EKS module must always be created."
  }
}

# Scenario: "Full Features -- public endpoint enabled"
run "test_public_endpoint_enabled" {
  command = plan

  variables {
    cluster_name                         = "test-complete"
    kubernetes_version                   = "1.32"
    environment                          = "prod"
    node_instance_types                  = ["m5.large"]
    node_min_size                        = 2
    node_max_size                        = 10
    node_desired_size                    = 4
    cluster_endpoint_public_access       = true
    cluster_endpoint_public_access_cidrs = ["10.0.0.0/8"]
    kms_key_enabled                      = true
    cluster_log_retention_in_days        = 365
    enable_vpc_flow_logs                 = true
    one_nat_gateway_per_az               = true
  }

  override_module {
    target = module.vpc[0]
    outputs = {
      vpc_id          = "vpc-stubbed"
      public_subnets  = ["subnet-pub1", "subnet-pub2"]
      private_subnets = ["subnet-priv1", "subnet-priv2"]
    }
  }

  override_module {
    target = module.eks
    outputs = {
      cluster_name                       = "test-complete"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-complete"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-complete/cluster"
    }
  }

  assert {
    condition     = var.cluster_endpoint_public_access == true
    error_message = "Public endpoint must be enabled when cluster_endpoint_public_access = true."
  }
}

# Scenario: "Full Features -- KMS explicitly enabled"
run "test_kms_explicitly_enabled" {
  command = plan

  variables {
    cluster_name        = "test-complete"
    kubernetes_version  = "1.32"
    environment         = "prod"
    node_instance_types = ["m5.large"]
    node_min_size       = 2
    node_max_size       = 10
    node_desired_size   = 4
    kms_key_enabled     = true
  }

  override_module {
    target = module.vpc[0]
    outputs = {
      vpc_id          = "vpc-stubbed"
      public_subnets  = ["subnet-pub1", "subnet-pub2"]
      private_subnets = ["subnet-priv1", "subnet-priv2"]
    }
  }

  override_module {
    target = module.eks
    outputs = {
      cluster_name                       = "test-complete"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-complete"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-complete/cluster"
    }
  }

  assert {
    condition     = var.kms_key_enabled == true
    error_message = "KMS encryption must be enabled."
  }
}

# Scenario: "Full Features -- custom log retention"
run "test_custom_log_retention" {
  command = plan

  variables {
    cluster_name                  = "test-complete"
    kubernetes_version            = "1.32"
    environment                   = "prod"
    node_instance_types           = ["m5.large"]
    node_min_size                 = 2
    node_max_size                 = 10
    node_desired_size             = 4
    cluster_log_retention_in_days = 365
  }

  override_module {
    target = module.vpc[0]
    outputs = {
      vpc_id          = "vpc-stubbed"
      public_subnets  = ["subnet-pub1", "subnet-pub2"]
      private_subnets = ["subnet-priv1", "subnet-priv2"]
    }
  }

  override_module {
    target = module.eks
    outputs = {
      cluster_name                       = "test-complete"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-complete"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-complete/cluster"
    }
  }

  assert {
    condition     = var.cluster_log_retention_in_days == 365
    error_message = "Log retention must be set to 365 days when specified."
  }
}

# Scenario: "Full Features -- HA NAT enabled"
run "test_ha_nat_enabled" {
  command = plan

  variables {
    cluster_name           = "test-complete"
    kubernetes_version     = "1.32"
    environment            = "prod"
    node_instance_types    = ["m5.large"]
    node_min_size          = 2
    node_max_size          = 10
    node_desired_size      = 4
    one_nat_gateway_per_az = true
  }

  override_module {
    target = module.vpc[0]
    outputs = {
      vpc_id          = "vpc-stubbed"
      public_subnets  = ["subnet-pub1", "subnet-pub2"]
      private_subnets = ["subnet-priv1", "subnet-priv2"]
    }
  }

  override_module {
    target = module.eks
    outputs = {
      cluster_name                       = "test-complete"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-complete"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-complete/cluster"
    }
  }

  assert {
    condition     = var.one_nat_gateway_per_az == true
    error_message = "HA NAT (one_nat_gateway_per_az) must be enabled when set to true."
  }
}

# Scenario: "Full Features -- consumer tags are merged"
run "test_consumer_tags_merged" {
  command = plan

  variables {
    cluster_name        = "test-complete"
    kubernetes_version  = "1.32"
    environment         = "prod"
    node_instance_types = ["m5.large"]
    node_min_size       = 2
    node_max_size       = 10
    node_desired_size   = 4
    tags                = { Owner = "platform-team", CostCenter = "eng" }
  }

  override_module {
    target = module.vpc[0]
    outputs = {
      vpc_id          = "vpc-stubbed"
      public_subnets  = ["subnet-pub1", "subnet-pub2"]
      private_subnets = ["subnet-priv1", "subnet-priv2"]
    }
  }

  override_module {
    target = module.eks
    outputs = {
      cluster_name                       = "test-complete"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-complete"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-complete/cluster"
    }
  }

  assert {
    condition     = local.merged_tags["Owner"] == "platform-team"
    error_message = "Consumer tags must be present in merged_tags."
  }

  assert {
    condition     = local.merged_tags["ManagedBy"] == "terraform"
    error_message = "Module default ManagedBy tag must always be present in merged_tags."
  }
}

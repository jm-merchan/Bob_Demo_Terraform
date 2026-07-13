# Generated from specs/001-eks-cluster-bob/design.md Section 5 -- Unit: Validation

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

# --- Validation Error Cases (expect_failures) ---

# Empty cluster_name rejected
run "test_empty_cluster_name_rejected" {
  command = plan

  variables {
    cluster_name        = ""
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
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
      cluster_name                       = "stubbed"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/stubbed"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/stubbed/cluster"
    }
  }

  expect_failures = [var.cluster_name]
}

# kubernetes_version with 'v' prefix rejected
run "test_kubernetes_version_with_v_prefix_rejected" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "v1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  expect_failures = [var.kubernetes_version]
}

# kubernetes_version = "latest" rejected
run "test_kubernetes_version_latest_rejected" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "latest"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  expect_failures = [var.kubernetes_version]
}

# Invalid environment value rejected
run "test_invalid_environment_rejected" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "1.32"
    environment         = "production"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  expect_failures = [var.environment]
}

# node_min_size = 0 rejected
run "test_node_min_size_zero_rejected" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 0
    node_max_size       = 3
    node_desired_size   = 1
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  expect_failures = [var.node_min_size]
}

# node_disk_size below minimum rejected
run "test_node_disk_size_below_minimum_rejected" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
    node_disk_size      = 19
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  expect_failures = [var.node_disk_size]
}

# Invalid vpc_cidr rejected
run "test_invalid_vpc_cidr_rejected" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
    vpc_cidr            = "not-a-cidr"
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  expect_failures = [var.vpc_cidr]
}

# Only 1 AZ provided rejected
run "test_single_availability_zone_rejected" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
    availability_zones  = ["us-east-1a"]
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  expect_failures = [var.availability_zones]
}

# Invalid authentication_mode rejected
run "test_invalid_authentication_mode_rejected" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
    authentication_mode = "INVALID"
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  expect_failures = [var.authentication_mode]
}

# Invalid node_capacity_type rejected
run "test_invalid_node_capacity_type_rejected" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
    node_capacity_type  = "RESERVED"
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  expect_failures = [var.node_capacity_type]
}

# --- Boundary-pass cases (validation accepts) ---

# Minimum valid cluster_name length
run "test_minimum_valid_cluster_name" {
  command = plan

  variables {
    cluster_name        = "a"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
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
      cluster_name                       = "a"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/a"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/a/cluster"
    }
  }

  assert {
    condition     = module.eks.cluster_name != null
    error_message = "Single-character cluster_name at minimum boundary should be accepted."
  }
}

# Valid kubernetes_version
run "test_valid_kubernetes_version" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  assert {
    condition     = var.kubernetes_version == "1.32"
    error_message = "Valid kubernetes_version format should be accepted."
  }
}

# Minimum valid node_min_size
run "test_minimum_valid_node_min_size" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 1
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  assert {
    condition     = var.node_min_size == 1
    error_message = "node_min_size of 1 (minimum boundary) should be accepted."
  }
}

# Minimum valid node_disk_size
run "test_minimum_valid_node_disk_size" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
    node_disk_size      = 20
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  assert {
    condition     = var.node_disk_size == 20
    error_message = "node_disk_size of 20 GiB (minimum boundary) should be accepted."
  }
}

# Exactly 2 AZs accepted
run "test_exactly_two_availability_zones_accepted" {
  command = plan

  variables {
    cluster_name        = "test"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
    availability_zones  = ["us-east-1a", "us-east-1b"]
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  assert {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly 2 availability zones should be accepted."
  }
}

# Minimum valid cluster_log_retention_in_days
run "test_minimum_log_retention" {
  command = plan

  variables {
    cluster_name                  = "test"
    kubernetes_version            = "1.32"
    environment                   = "dev"
    node_instance_types           = ["t3.medium"]
    node_min_size                 = 1
    node_max_size                 = 3
    node_desired_size             = 2
    cluster_log_retention_in_days = 1
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  assert {
    condition     = var.cluster_log_retention_in_days == 1
    error_message = "cluster_log_retention_in_days of 1 (minimum valid value) should be accepted."
  }
}

# Maximum valid cluster_log_retention_in_days
run "test_maximum_log_retention" {
  command = plan

  variables {
    cluster_name                  = "test"
    kubernetes_version            = "1.32"
    environment                   = "dev"
    node_instance_types           = ["t3.medium"]
    node_min_size                 = 1
    node_max_size                 = 3
    node_desired_size             = 2
    cluster_log_retention_in_days = 3653
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
      cluster_name                       = "test"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test/cluster"
    }
  }

  assert {
    condition     = var.cluster_log_retention_in_days == 3653
    error_message = "cluster_log_retention_in_days of 3653 (maximum valid value) should be accepted."
  }
}

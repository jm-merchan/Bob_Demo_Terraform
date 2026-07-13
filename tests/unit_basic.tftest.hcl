# Generated from specs/001-eks-cluster-bob/design.md Section 5 -- Unit: Secure Defaults
# The eks/vpc modules use terraform-aws-modules internally with data source count expressions
# that depend on computed values. We use override_module to stub those modules and test
# only root module logic (locals, variable defaults, module instantiation counts).

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

# Scenario: "Secure Defaults -- public endpoint is OFF by default"
run "test_public_endpoint_off_by_default" {
  command = plan

  variables {
    cluster_name        = "test-basic"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
  }

  # Stub out the module internals — we test root-level defaults, not module internals
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
      cluster_name                       = "test-basic"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-basic"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-basic/cluster"
    }
  }

  assert {
    condition     = var.cluster_endpoint_public_access == false
    error_message = "cluster_endpoint_public_access must default to false (Security Hub EKS.1)."
  }
}

# Scenario: "Secure Defaults -- KMS encryption is ON by default"
run "test_kms_enabled_by_default" {
  command = plan

  variables {
    cluster_name        = "test-basic"
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
      cluster_name                       = "test-basic"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-basic"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-basic/cluster"
    }
  }

  assert {
    condition     = var.kms_key_enabled == true
    error_message = "kms_key_enabled must default to true (Security Hub EKS.3)."
  }
}

# Scenario: "Secure Defaults -- all 5 control plane log types enabled"
run "test_all_log_types_enabled_by_default" {
  command = plan

  variables {
    cluster_name        = "test-basic"
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
      cluster_name                       = "test-basic"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-basic"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-basic/cluster"
    }
  }

  assert {
    condition     = length(var.cluster_log_types) == 5
    error_message = "All 5 control plane log types must be enabled by default (Security Hub EKS.8)."
  }
}

# Scenario: "Secure Defaults -- IRSA enabled by default"
run "test_irsa_enabled_by_default" {
  command = plan

  variables {
    cluster_name        = "test-basic"
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
      cluster_name                       = "test-basic"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-basic"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-basic/cluster"
    }
  }

  assert {
    condition     = var.enable_irsa == true
    error_message = "enable_irsa must default to true."
  }
}

# Scenario: "Secure Defaults -- default tags include ManagedBy=terraform"
run "test_default_tags_present" {
  command = plan

  variables {
    cluster_name        = "test-basic"
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
      cluster_name                       = "test-basic"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-basic"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-basic/cluster"
    }
  }

  assert {
    condition     = local.default_tags["ManagedBy"] == "terraform"
    error_message = "default_tags must include ManagedBy=terraform."
  }

  assert {
    condition     = local.default_tags["Environment"] == "dev"
    error_message = "default_tags must include the Environment tag set to the environment variable value."
  }
}

# Scenario: "Secure Defaults -- VPC is created when vpc_id not provided"
run "test_vpc_created_when_no_vpc_id" {
  command = plan

  variables {
    cluster_name        = "test-basic"
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
      cluster_name                       = "test-basic"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-basic"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-basic/cluster"
    }
  }

  assert {
    condition     = local.create_vpc == true
    error_message = "create_vpc must be true when vpc_id is not provided."
  }

  assert {
    condition     = length(module.vpc) == 1
    error_message = "VPC module must be instantiated when vpc_id is not provided."
  }
}

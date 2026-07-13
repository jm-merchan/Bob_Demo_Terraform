# Generated from specs/001-eks-cluster-bob/design.md Section 5 -- Unit: Edge Cases

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

# Sub-scenario: "BYO-VPC suppresses VPC module"
run "test_byovpc_suppresses_vpc_module" {
  command = plan

  variables {
    cluster_name        = "test-byovpc"
    kubernetes_version  = "1.32"
    environment         = "staging"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
    vpc_id              = "vpc-0123456789abcdef0"
    private_subnet_ids  = ["subnet-aaa", "subnet-bbb"]
    public_subnet_ids   = ["subnet-ccc", "subnet-ddd"]
  }

  # vpc_id is provided → module.vpc[0] does not exist (count=0); do not override it
  override_module {
    target = module.eks
    outputs = {
      cluster_name                       = "test-byovpc"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-byovpc"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-byovpc/cluster"
    }
  }

  assert {
    condition     = length(module.vpc) == 0
    error_message = "VPC module must NOT be created when vpc_id is provided."
  }

  assert {
    condition     = module.eks.cluster_name != null
    error_message = "EKS module must still be created when using an existing VPC."
  }
}

# Sub-scenario: "BYO-VPC uses provided subnet IDs"
run "test_byovpc_uses_provided_subnets" {
  command = plan

  variables {
    cluster_name        = "test-byovpc-subnets"
    kubernetes_version  = "1.32"
    environment         = "staging"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
    vpc_id              = "vpc-0123456789abcdef0"
    private_subnet_ids  = ["subnet-aaa", "subnet-bbb"]
    public_subnet_ids   = ["subnet-ccc", "subnet-ddd"]
  }

  # vpc_id is provided → module.vpc[0] does not exist (count=0); do not override it
  override_module {
    target = module.eks
    outputs = {
      cluster_name                       = "test-byovpc-subnets"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-byovpc-subnets"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-byovpc-subnets/cluster"
    }
  }

  assert {
    condition     = local.create_vpc == false
    error_message = "create_vpc local must be false when vpc_id is provided."
  }

  assert {
    condition     = local.vpc_id == "vpc-0123456789abcdef0"
    error_message = "local.vpc_id must equal the provided vpc_id."
  }

  assert {
    condition     = length(local.private_subnet_ids) == 2
    error_message = "local.private_subnet_ids must use the provided private_subnet_ids."
  }
}

# Sub-scenario: "KMS disabled -- EKS module still created"
run "test_kms_disabled_eks_still_created" {
  command = plan

  variables {
    cluster_name        = "test-nokms"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
    kms_key_enabled     = false
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
      cluster_name                       = "test-nokms"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-nokms"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-nokms/cluster"
    }
  }

  assert {
    condition     = module.eks.cluster_name != null
    error_message = "EKS module must still be created when KMS is disabled."
  }

  assert {
    condition     = var.kms_key_enabled == false
    error_message = "kms_key_enabled must be false when explicitly set to false."
  }
}

# Sub-scenario: "Public endpoint with CIDR restriction"
run "test_public_endpoint_with_cidr_restriction" {
  command = plan

  variables {
    cluster_name                         = "test-pubcidr"
    kubernetes_version                   = "1.32"
    environment                          = "dev"
    node_instance_types                  = ["t3.medium"]
    node_min_size                        = 1
    node_max_size                        = 3
    node_desired_size                    = 2
    cluster_endpoint_public_access       = true
    cluster_endpoint_public_access_cidrs = ["192.168.1.0/24"]
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
      cluster_name                       = "test-pubcidr"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-pubcidr"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-pubcidr/cluster"
    }
  }

  assert {
    condition     = var.cluster_endpoint_public_access == true
    error_message = "cluster_endpoint_public_access must be true when set."
  }

  assert {
    condition     = var.cluster_endpoint_public_access_cidrs == tolist(["192.168.1.0/24"])
    error_message = "cluster_endpoint_public_access_cidrs must match the provided value."
  }
}

# Sub-scenario: "SPOT capacity type with multiple instance types"
run "test_spot_capacity_multiple_instance_types" {
  command = plan

  variables {
    cluster_name        = "test-spot"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium", "t3.large"]
    node_min_size       = 1
    node_max_size       = 5
    node_desired_size   = 2
    node_capacity_type  = "SPOT"
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
      cluster_name                       = "test-spot"
      cluster_endpoint                   = "https://stubbed.eks.endpoint"
      cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/test-spot"
      cluster_certificate_authority_data = "c3R1YmJlZA=="
      cluster_oidc_issuer_url            = "https://oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/stubbed"
      cluster_security_group_id          = "sg-stubbed"
      node_security_group_id             = "sg-node-stubbed"
      cluster_iam_role_arn               = "arn:aws:iam::123456789012:role/stubbed-cluster-role"
      node_iam_role_arn                  = "arn:aws:iam::123456789012:role/stubbed-node-role"
      cloudwatch_log_group_name          = "/aws/eks/test-spot/cluster"
    }
  }

  assert {
    condition     = var.node_capacity_type == "SPOT"
    error_message = "node_capacity_type must be SPOT when set."
  }

  assert {
    condition     = length(var.node_instance_types) == 2
    error_message = "node_instance_types must support multiple instance types for SPOT."
  }
}

# Generated from specs/001-eks-cluster-bob/design.md Section 5 — Integration: End-to-End
# Requires real AWS credentials and creates real infrastructure (~20 min, incurs cost).
# NOT run during this workflow.
# Run with: TF_VAR_cluster_name=... terraform test -filter=tests/integration.tftest.hcl

# Scenario: "End-to-End Cluster Creation — verify EKS cluster, node group, and VPC are functional"
# integration
run "test_integration_end_to_end" {
  command = apply

  variables {
    cluster_name        = "test-integration"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 2
    node_desired_size   = 1
  }

  assert {
    condition     = module.eks.cluster_endpoint != null && module.eks.cluster_endpoint != ""
    error_message = "Cluster endpoint must be available after apply."
  }

  assert {
    condition     = module.eks.cluster_arn != null
    error_message = "Cluster ARN must be set after apply."
  }

  assert {
    condition     = module.eks.worker_iam_role_arn != null
    error_message = "Worker IAM role ARN must be set after apply."
  }

  assert {
    condition     = output.vpc_id != null && output.vpc_id != ""
    error_message = "VPC ID output must be populated after apply."
  }

  assert {
    condition     = length(output.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets must be created."
  }
}

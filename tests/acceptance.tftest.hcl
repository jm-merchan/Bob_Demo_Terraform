# Generated from specs/001-eks-cluster-bob/design.md Section 5 — Acceptance: Plan Verification
# Requires real AWS credentials. NOT run during this workflow.
# Run with: TF_VAR_cluster_name=... terraform test -filter=tests/acceptance.tftest.hcl

# Scenario: "Plan Verification — resolve plan-unknown attributes with real AWS APIs"
# acceptance
run "test_acceptance_plan_verification" {
  command = plan

  variables {
    cluster_name        = "test-acceptance"
    kubernetes_version  = "1.32"
    environment         = "dev"
    node_instance_types = ["t3.medium"]
    node_min_size       = 1
    node_max_size       = 3
    node_desired_size   = 2
  }

  # Cluster endpoint URL should be a non-empty string
  assert {
    condition     = module.eks.cluster_endpoint != null && module.eks.cluster_endpoint != ""
    error_message = "cluster_endpoint must be a non-empty string from real AWS APIs."
  }

  # Cluster ARN should be non-empty
  assert {
    condition     = module.eks.cluster_arn != null && module.eks.cluster_arn != ""
    error_message = "cluster_arn must be a non-empty ARN from real AWS APIs."
  }

  # OIDC issuer URL should be a non-empty https URL
  assert {
    condition     = module.eks.cluster_oidc_issuer_url != null && module.eks.cluster_oidc_issuer_url != ""
    error_message = "cluster_oidc_issuer_url must be a non-empty URL from real AWS APIs."
  }
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "URL of the EKS API server endpoint."
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = module.eks_cluster.cluster_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data required for kubeconfig generation."
  sensitive   = true
  value       = module.eks_cluster.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for configuring IAM Roles for Service Accounts (IRSA)."
  value       = "https://${module.eks_cluster.oidc_provider}"
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC identity provider — used to create IRSA IAM role trust policies."
  value       = module.eks_cluster.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "ID of the cluster security group created by EKS."
  value       = module.eks_cluster.cluster_security_group_id
}

output "node_security_group_id" {
  description = "ID of the shared node security group."
  value       = module.eks_cluster.node_security_group_id
}

output "cluster_iam_role_arn" {
  description = "ARN of the IAM role attached to the EKS control plane."
  value       = module.eks_cluster.cluster_iam_role_arn
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role attached to EKS managed nodes."
  value       = try(module.eks_cluster.eks_managed_node_groups["default"].iam_role_arn, null)
}

# Alias preserved for downstream compatibility
output "worker_iam_role_arn" {
  description = "ARN of the IAM role attached to EKS worker nodes (alias for node_iam_role_arn)."
  value       = try(module.eks_cluster.eks_managed_node_groups["default"].iam_role_arn, null)
}

output "kms_policy_arn" {
  description = "ARN of the KMS key used for EKS secrets encryption."
  value       = try(module.eks_cluster.kms_key_arn, null)
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for EKS control plane logs."
  value       = module.eks_cluster.cloudwatch_log_group_name
}

output "vpc_id" {
  description = "ID of the VPC used by the EKS cluster (created or provided)."
  value       = module.eks_cluster.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used by worker nodes."
  value       = module.eks_cluster.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets used by load balancer ENIs."
  value       = module.eks_cluster.public_subnet_ids
}

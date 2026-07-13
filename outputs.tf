output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "URL of the EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = module.eks.cluster_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data required for kubeconfig generation."
  sensitive   = true
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for configuring IAM Roles for Service Accounts (IRSA)."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC identity provider — used to create IRSA IAM role trust policies."
  value       = module.eks.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "ID of the cluster security group created by EKS."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "ID of the shared node security group."
  value       = module.eks.node_security_group_id
}

output "cluster_iam_role_arn" {
  description = "ARN of the IAM role attached to the EKS control plane."
  value       = module.eks.cluster_iam_role_arn
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role attached to EKS managed nodes."
  value       = module.eks.node_iam_role_arn
}

# Alias preserved for design §3 contract compatibility
output "worker_iam_role_arn" {
  description = "ARN of the IAM role attached to EKS worker nodes (alias for node_iam_role_arn)."
  value       = module.eks.node_iam_role_arn
}

output "worker_iam_role_name" {
  description = "Name of the IAM role attached to EKS worker nodes."
  value       = module.eks.node_iam_role_name
}

output "kms_policy_arn" {
  description = "ARN of the KMS key policy for EKS secrets encryption. Null when kms_key_enabled is false."
  value       = try(module.eks.kms_policy_arn, null)
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for EKS control plane logs."
  value       = module.eks.cloudwatch_log_group_name
}

output "vpc_id" {
  description = "ID of the VPC used by the EKS cluster (created or provided)."
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used by worker nodes."
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets used by load balancer ENIs."
  value       = local.public_subnet_ids
}

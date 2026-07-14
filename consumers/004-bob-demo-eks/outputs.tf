output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server URL."
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = module.eks_cluster.cluster_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate."
  sensitive   = true
  value       = module.eks_cluster.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA trust policies."
  value       = module.eks_cluster.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA IAM role trust documents."
  value       = module.eks_cluster.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "Cluster-managed security group ID."
  value       = module.eks_cluster.cluster_security_group_id
}

output "vpc_id" {
  description = "VPC ID created by the module."
  value       = module.eks_cluster.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by worker nodes."
  value       = module.eks_cluster.private_subnet_ids
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for control-plane logs."
  value       = module.eks_cluster.cloudwatch_log_group_name
}

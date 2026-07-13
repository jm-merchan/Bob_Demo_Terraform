output "cluster_name" {
  description = "Name of the deployed EKS cluster."
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

output "oidc_provider_arn" {
  description = "ARN of the OIDC identity provider for IRSA."
  value       = module.eks_cluster.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "ID of the cluster security group."
  value       = module.eks_cluster.cluster_security_group_id
}

output "vpc_id" {
  description = "ID of the VPC created for the cluster."
  value       = module.eks_cluster.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets for worker nodes."
  value       = module.eks_cluster.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets for load balancer ENIs."
  value       = module.eks_cluster.public_subnet_ids
}

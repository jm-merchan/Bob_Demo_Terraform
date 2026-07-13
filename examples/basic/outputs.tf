output "cluster_name" {
  description = "Name of the deployed EKS cluster."
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "URL of the EKS API server endpoint."
  value       = module.eks_cluster.cluster_endpoint
}

output "vpc_id" {
  description = "ID of the VPC created for the cluster."
  value       = module.eks_cluster.vpc_id
}
